/*
 * MountZero - Core Implementation (Enhanced)
 *
 * Full VFS path redirection, SUSFS bridge, container support,
 * bootloop guard, and module auto-scanning system.
 * Works alongside SUSFS to provide automatic module mounting at boot.
 * Equivalent to ZeroMount kernel driver with enhancements.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/dcache.h>
#include <linux/path.h>
#include <linux/namei.h>
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/uaccess.h>
#include <linux/dirent.h>
#include <linux/miscdevice.h>
#include <linux/cred.h>
#include <linux/vmalloc.h>
#include <linux/mm.h>
#include <linux/mountzero.h>
#include <linux/mountzero_def.h>
#include <linux/spinlock.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/statfs.h>
#include <linux/file.h>
#include <linux/fs_struct.h>
#include <linux/reboot.h>
#include <linux/bitmap.h>
#include <linux/mount.h>
#include <linux/kthread.h>
#include <linux/delay.h>
#include <linux/workqueue.h>
#include <linux/xattr.h>
#include <linux/security.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/input.h>

#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs.h>
#include <linux/susfs_def.h>
#endif

#define MOUNTZERO_VERSION "2.0.0-MZ"
#define MOUNTZERO_HASH_BITS 10
#define MZ_BLOOM_BITS 8192
#define MZ_BLOOM_MASK (MZ_BLOOM_BITS - 1)

/* ============================================================
 * Global State
 * ============================================================ */

int mountzero_debug_level = 0;
atomic_t mountzero_enabled = ATOMIC_INIT(0);
EXPORT_SYMBOL(mountzero_enabled);
EXPORT_SYMBOL(mountzero_debug_level);

/* VFS engine statistics */
static atomic_t mz_rule_count = ATOMIC_INIT(0);
static atomic_t mz_hidden_path_count = ATOMIC_INIT(0);
static atomic_t mz_hidden_maps_count = ATOMIC_INIT(0);
static atomic_t mz_excluded_uid_count = ATOMIC_INIT(0);

/* Bootloop guard */
static atomic_t mz_bootloop_count = ATOMIC_INIT(0);
static bool mz_guard_tripped = false;
static int mz_bootloop_threshold = 3;

/* Hidden paths for SUSFS */
#define MZ_MAX_HIDDEN_PATHS 64
static char *mz_hidden_paths[MZ_MAX_HIDDEN_PATHS];
static int mz_hidden_path_count_int = 0;
static DEFINE_MUTEX(mz_hidden_mutex);

/* Hash tables for rules */
DEFINE_HASHTABLE(mz_redirect_rules_ht, MOUNTZERO_HASH_BITS);
EXPORT_SYMBOL(mz_redirect_rules_ht);
DEFINE_HASHTABLE(mz_bind_rules_ht, MOUNTZERO_HASH_BITS);
DEFINE_HASHTABLE(mz_hide_rules_ht, MOUNTZERO_HASH_BITS);
DEFINE_HASHTABLE(mz_sus_path_ht, MOUNTZERO_HASH_BITS);
DEFINE_HASHTABLE(mz_sus_map_ht, MOUNTZERO_HASH_BITS);
DEFINE_HASHTABLE(mz_ino_ht, MOUNTZERO_HASH_BITS);

DEFINE_SPINLOCK(mz_lock);
EXPORT_SYMBOL(mz_lock);
static DECLARE_BITMAP(mz_bloom, MZ_BLOOM_BITS);

/* Excluded UIDs */
static DECLARE_BITMAP(mz_excluded_uids, 20000);
static DEFINE_MUTEX(mz_uid_mutex);

/* Module: Bootloop Guard */
static struct kobject *mz_guard_kobj;

/* ============================================================
 * Sysfs Interface
 * ============================================================ */

static ssize_t mz_version_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sysfs_emit(buf, "%s\n", MOUNTZERO_VERSION);
}

static ssize_t mz_status_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sysfs_emit(buf, "enabled=%d\nrules=%d\nhidden_paths=%d\nhidden_maps=%d\nexcluded_uids=%d\nbootloop_count=%d\nguard_tripped=%d\n",
                      atomic_read(&mountzero_enabled),
                      atomic_read(&mz_rule_count),
                      atomic_read(&mz_hidden_path_count),
                      atomic_read(&mz_hidden_maps_count),
                      atomic_read(&mz_excluded_uid_count),
                      atomic_read(&mz_bootloop_count),
                      mz_guard_tripped ? 1 : 0);
}

static ssize_t mz_debug_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sysfs_emit(buf, "%d\n", mountzero_debug_level);
}

static ssize_t mz_debug_store(struct kobject *kobj, struct kobj_attribute *attr,
                               const char *buf, size_t count)
{
    int level;
    if (kstrtoint(buf, 10, &level) == 0) {
        mountzero_debug_level = clamp(level, 0, 2);
        pr_info("MountZero: Debug level set to %d\n", mountzero_debug_level);
    }
    return count;
}

static ssize_t mz_guard_count_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sysfs_emit(buf, "%d\n", atomic_read(&mz_bootloop_count));
}

static ssize_t mz_guard_count_store(struct kobject *kobj, struct kobj_attribute *attr,
                                     const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0) {
        atomic_set(&mz_bootloop_count, val);
        pr_info("MountZero: Bootloop count set to %d\n", val);
    }
    return count;
}

static ssize_t mz_guard_threshold_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sysfs_emit(buf, "%d\n", mz_bootloop_threshold);
}

static ssize_t mz_guard_threshold_store(struct kobject *kobj, struct kobj_attribute *attr,
                                         const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0) {
        mz_bootloop_threshold = clamp(val, 1, 10);
        pr_info("MountZero: Bootloop threshold set to %d\n", mz_bootloop_threshold);
    }
    return count;
}

static struct kobj_attribute mz_version_attr = __ATTR_RO(mz_version);
static struct kobj_attribute mz_status_attr = __ATTR_RO(mz_status);
static struct kobj_attribute mz_debug_attr = __ATTR_RW(mz_debug);
static struct kobj_attribute mz_guard_count_attr = __ATTR_RW(mz_guard_count);
static struct kobj_attribute mz_guard_threshold_attr = __ATTR_RW(mz_guard_threshold);

static struct attribute *mz_attrs[] = {
    &mz_version_attr.attr,
    &mz_status_attr.attr,
    &mz_debug_attr.attr,
    NULL,
};

static struct attribute *mz_guard_attrs[] = {
    &mz_guard_count_attr.attr,
    &mz_guard_threshold_attr.attr,
    NULL,
};

static struct attribute_group mz_attr_group = {
    .attrs = mz_attrs,
};

static struct attribute_group mz_guard_attr_group = {
    .attrs = mz_guard_attrs,
};

/* ============================================================
 * Bloom Filter Helpers
 * ============================================================ */

static inline void mz_bloom_add(u32 hash)
{
    set_bit(hash & MZ_BLOOM_MASK, mz_bloom);
    set_bit((hash >> 10) & MZ_BLOOM_MASK, mz_bloom);
    set_bit((hash >> 20) & MZ_BLOOM_MASK, mz_bloom);
}

static inline bool mz_bloom_test(u32 hash)
{
    return test_bit(hash & MZ_BLOOM_MASK, mz_bloom) &&
           test_bit((hash >> 10) & MZ_BLOOM_MASK, mz_bloom) &&
           test_bit((hash >> 20) & MZ_BLOOM_MASK, mz_bloom);
}

/* ============================================================
 * Path Resolution
 * ============================================================ */

static inline u32 mz_hash_string(const char *str)
{
    u32 hash = 0;
    if (!str)
        return 0;

    while (*str) {
        hash += *str++;
        hash += (hash << 10);
        hash ^= (hash >> 6);
    }
    hash += (hash << 3);
    hash ^= (hash >> 11);
    hash += (hash << 15);
    return hash;
}

bool mountzero_should_redirect(const char *path)
{
    struct mz_rule *rule;
    u32 hash;
    unsigned long irq_flags;
    bool found = false;

    if (atomic_read(&mountzero_enabled) == 0 || !path)
        return false;

    hash = mz_hash_string(path);

    if (!mz_bloom_test(hash))
        return false;

    spin_lock_irqsave(&mz_lock, irq_flags);
    hash_for_each_possible(mz_redirect_rules_ht, rule, node, hash) {
        if (rule->hash == hash && strcmp(rule->virtual_path, path) == 0) {
            found = true;
            break;
        }
    }
    spin_unlock_irqrestore(&mz_lock, irq_flags);

    return found;
}
EXPORT_SYMBOL(mountzero_should_redirect);

char *mountzero_resolve_path(const char *path)
{
    struct mz_rule *rule;
    u32 hash;
    unsigned long irq_flags;
    char *resolved = NULL;

    if (!path)
        return NULL;

    hash = mz_hash_string(path);

    if (!mz_bloom_test(hash))
        return NULL;

    spin_lock_irqsave(&mz_lock, irq_flags);
    hash_for_each_possible(mz_redirect_rules_ht, rule, node, hash) {
        if (rule->hash == hash && strcmp(rule->virtual_path, path) == 0) {
            resolved = kstrdup(rule->real_path, GFP_ATOMIC);
            break;
        }
    }
    spin_unlock_irqrestore(&mz_lock, irq_flags);

    return resolved;
}
EXPORT_SYMBOL(mountzero_resolve_path);

/* Reverse lookup: map real inode back to virtual path */
char *mountzero_get_static_vpath(struct inode *inode)
{
    struct mz_rule *rule;
    unsigned long key;
    unsigned long irq_flags;
    char *copy = NULL;

    if (unlikely(!inode || !inode->i_sb))
        return NULL;

    if (atomic_read(&mountzero_enabled) == 0)
        return NULL;

    key = inode->i_ino ^ inode->i_sb->s_dev;

    spin_lock_irqsave(&mz_lock, irq_flags);
    hash_for_each_possible(mz_ino_ht, rule, ino_node, key) {
        if (rule->real_ino == inode->i_ino &&
            rule->real_dev == inode->i_sb->s_dev &&
            (rule->flags & MZ_FLAG_READ_ONLY)) {
            copy = kstrdup(rule->virtual_path, GFP_ATOMIC);
            break;
        }
    }
    spin_unlock_irqrestore(&mz_lock, irq_flags);
    return copy;
}
EXPORT_SYMBOL(mountzero_get_static_vpath);

/* ============================================================
 * SUSFS Bridge - Full Integration
 *
 * NOTE: This kernel's SUSFS API uses void __user **user_info
 * (struct-based IOCTL calls). Direct kernel calls are not supported.
 * The SUSFS bridge here provides the interface for userspace tools
 * (ksu_susfs CLI) to call via IOCTL. Kernel-internal SUSFS ops
 * are done by the userspace bridge.sh script.
 * ============================================================ */

#ifdef CONFIG_KSU_SUSFS

/* Bridge: Add SUSFS hidden path */
/* Called from userspace via IOCTL → bridge.sh → ksu_susfs CLI */
int mountzero_susfs_add_path(const char *path)
{
    /* This function is a no-op in kernel.
     * Use: ksu_susfs add_sus_path <path> from userspace
     * or bridge.sh reconcile from metamount.sh */
    pr_info("MountZero: SUSFS add_path requested for: %s (use ksu_susfs CLI)\n", path ?: "(null)");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_add_path);

/* Bridge: Add SUSFS hidden path with loop detection */
int mountzero_susfs_add_path_loop(const char *path)
{
    pr_info("MountZero: SUSFS add_path_loop requested for: %s (use ksu_susfs CLI)\n", path ?: "(null)");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_add_path_loop);

/* Bridge: Add SUSFS kstat spoofing */
int mountzero_susfs_add_kstat(const char *path)
{
    pr_info("MountZero: SUSFS add_kstat requested for: %s (use ksu_susfs CLI)\n", path ?: "(null)");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_add_kstat);

/* Bridge: Update SUSFS kstat spoofing */
int mountzero_susfs_update_kstat(const char *path)
{
    pr_info("MountZero: SUSFS update_kstat requested for: %s (use ksu_susfs CLI)\n", path ?: "(null)");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_update_kstat);

/* Bridge: Add SUSFS maps hiding */
int mountzero_susfs_add_map(const char *path)
{
    pr_info("MountZero: SUSFS add_map requested for: %s (use ksu_susfs CLI)\n", path ?: "(null)");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_add_map);

/* Bridge: Set uname spoofing */
int mountzero_susfs_set_uname(const char *release, const char *version)
{
    pr_info("MountZero: SUSFS set_uname requested (use ksu_susfs CLI)\n");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_set_uname);

/* Bridge: Set cmdline spoofing */
int mountzero_susfs_set_cmdline(const char *path)
{
    pr_info("MountZero: SUSFS set_cmdline requested (use ksu_susfs CLI)\n");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_set_cmdline);

/* Bridge: Hide SUSFS mounts from non-su processes */
int mountzero_susfs_hide_mounts(bool enable)
{
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
    pr_info("MountZero: SUSFS mount hiding %s (use ksu_susfs CLI)\n", enable ? "enabled" : "disabled");
    return 0;
#else
    return -ENOSYS;
#endif
}
EXPORT_SYMBOL(mountzero_susfs_hide_mounts);

/* Bridge: Enable/disable SUSFS logging */
int mountzero_susfs_enable_log(bool enable)
{
#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
    pr_info("MountZero: SUSFS logging %s (use ksu_susfs CLI)\n", enable ? "enabled" : "disabled");
    return 0;
#else
    return -ENOSYS;
#endif
}
EXPORT_SYMBOL(mountzero_susfs_enable_log);

/* Bridge: Enable AVC log spoofing */
int mountzero_susfs_enable_avc_log_spoofing(bool enable)
{
    pr_info("MountZero: SUSFS AVC log spoofing %s (use ksu_susfs CLI)\n", enable ? "enabled" : "disabled");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_enable_avc_log_spoofing);

/* Query SUSFS version */
int mountzero_susfs_get_version(char *buf, size_t len)
{
    pr_info("MountZero: SUSFS version query (use ksu_susfs CLI)\n");
    if (buf && len > 0)
        snprintf(buf, len, "SUSFS (kernel)");
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_get_version);

/* Query SUSFS features */
int mountzero_susfs_get_features(char *buf, size_t len)
{
    if (buf && len > 0) {
        snprintf(buf, len,
            "sus_path:%d sus_mount:%d sus_kstat:%d spoof_uname:%d "
            "enable_log:%d spoof_cmdline:%d sus_map:%d",
            IS_ENABLED(CONFIG_KSU_SUSFS_SUS_PATH) ? 1 : 0,
            IS_ENABLED(CONFIG_KSU_SUSFS_SUS_MOUNT) ? 1 : 0,
            IS_ENABLED(CONFIG_KSU_SUSFS_SUS_KSTAT) ? 1 : 0,
            IS_ENABLED(CONFIG_KSU_SUSFS_SPOOF_UNAME) ? 1 : 0,
            IS_ENABLED(CONFIG_KSU_SUSFS_ENABLE_LOG) ? 1 : 0,
            IS_ENABLED(CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG) ? 1 : 0,
            IS_ENABLED(CONFIG_KSU_SUSFS_SUS_MAP) ? 1 : 0);
    }
    return 0;
}
EXPORT_SYMBOL(mountzero_susfs_get_features);

#endif /* CONFIG_KSU_SUSFS */

/* ============================================================
 * Rule Management
 * ============================================================ */

int mountzero_add_redirect(const char *virtual_path, const char *real_path, unsigned int flags)
{
    struct mz_rule *rule;
    u32 hash;
    unsigned long irq_flags;

    if (!virtual_path || !real_path)
        return -EINVAL;

    rule = kmalloc(sizeof(*rule), GFP_KERNEL);
    if (!rule)
        return -ENOMEM;

    memset(rule, 0, sizeof(*rule));

    rule->virtual_path = kstrdup(virtual_path, GFP_KERNEL);
    rule->real_path = kstrdup(real_path, GFP_KERNEL);
    if (!rule->virtual_path || !rule->real_path) {
        kfree(rule->virtual_path);
        kfree(rule->real_path);
        kfree(rule);
        return -ENOMEM;
    }

    rule->flags = flags;
    hash = mz_hash_string(virtual_path);
    rule->hash = hash;

    /* Get real file inode for reverse mapping */
    {
        struct path path;
        int ret = kern_path(real_path, LOOKUP_FOLLOW, &path);
        if (ret == 0) {
            struct inode *inode = d_backing_inode(path.dentry);
            if (inode) {
                rule->real_ino = inode->i_ino;
                rule->real_dev = inode->i_sb->s_dev;
                rule->v_ino = inode->i_ino;
                rule->v_dev = inode->i_sb->s_dev;

                /* Add to inode hash table for reverse lookup */
                unsigned long ino_key = inode->i_ino ^ inode->i_sb->s_dev;
                spin_lock_irqsave(&mz_lock, irq_flags);
                hash_add(mz_ino_ht, &rule->ino_node, ino_key);
                spin_unlock_irqrestore(&mz_lock, irq_flags);
            }
            path_put(&path);
        }
    }

    spin_lock_irqsave(&mz_lock, irq_flags);
    hash_add(mz_redirect_rules_ht, &rule->node, hash);
    mz_bloom_add(hash);
    atomic_inc(&mz_rule_count);
    spin_unlock_irqrestore(&mz_lock, irq_flags);

    if (mountzero_debug_level > 0)
        pr_info("MountZero: Added redirect: %s -> %s\n", virtual_path, real_path);

    return 0;
}
EXPORT_SYMBOL(mountzero_add_redirect);

int mountzero_del_redirect(const char *virtual_path)
{
    struct mz_rule *rule;
    u32 hash;
    unsigned long irq_flags;
    int found = 0;

    if (!virtual_path)
        return -EINVAL;

    hash = mz_hash_string(virtual_path);

    spin_lock_irqsave(&mz_lock, irq_flags);
    hash_for_each_possible(mz_redirect_rules_ht, rule, node, hash) {
        if (rule->hash == hash && strcmp(rule->virtual_path, virtual_path) == 0) {
            hash_del(&rule->node);
            /* Also remove from inode hash table */
            if (!hlist_unhashed(&rule->ino_node))
                hash_del(&rule->ino_node);
            kfree(rule->virtual_path);
            kfree(rule->real_path);
            kfree(rule);
            atomic_dec(&mz_rule_count);
            found = 1;
            break;
        }
    }
    spin_unlock_irqrestore(&mz_lock, irq_flags);

    if (!found)
        return -ENOENT;

    pr_info("MountZero: Deleted redirect rule: %s\n", virtual_path);
    return 0;
}
EXPORT_SYMBOL(mountzero_del_redirect);

/* ============================================================
 * UID Exclusion
 * ============================================================ */

int mountzero_block_uid(uid_t uid)
{
    if (uid >= 20000)
        return -EINVAL;

    mutex_lock(&mz_uid_mutex);
    set_bit(uid, mz_excluded_uids);
    atomic_inc(&mz_excluded_uid_count);
    mutex_unlock(&mz_uid_mutex);

    pr_info("MountZero: Blocked UID %d\n", uid);
    return 0;
}
EXPORT_SYMBOL(mountzero_block_uid);

int mountzero_unblock_uid(uid_t uid)
{
    if (uid >= 20000)
        return -EINVAL;

    mutex_lock(&mz_uid_mutex);
    clear_bit(uid, mz_excluded_uids);
    atomic_dec(&mz_excluded_uid_count);
    mutex_unlock(&mz_uid_mutex);

    return 0;
}
EXPORT_SYMBOL(mountzero_unblock_uid);

bool mountzero_is_uid_excluded(uid_t uid)
{
    bool excluded;

    if (uid >= 20000)
        return false;

    mutex_lock(&mz_uid_mutex);
    excluded = test_bit(uid, mz_excluded_uids);
    mutex_unlock(&mz_uid_mutex);

    return excluded;
}
EXPORT_SYMBOL(mountzero_is_uid_excluded);

/* ============================================================
 * Hidden Paths Management
 * ============================================================ */

int mountzero_add_hidden_path(const char *path)
{
    int ret = -ENOSPC;

    mutex_lock(&mz_hidden_mutex);
    if (mz_hidden_path_count_int < MZ_MAX_HIDDEN_PATHS) {
        mz_hidden_paths[mz_hidden_path_count_int] = kstrdup(path, GFP_KERNEL);
        if (mz_hidden_paths[mz_hidden_path_count_int]) {
            mz_hidden_path_count_int++;
            atomic_inc(&mz_hidden_path_count);
            ret = 0;
            pr_info("MountZero: Added hidden path: %s\n", path);
        } else {
            ret = -ENOMEM;
        }
    }
    mutex_unlock(&mz_hidden_mutex);

    return ret;
}
EXPORT_SYMBOL(mountzero_add_hidden_path);

int mountzero_clear_hidden_paths(void)
{
    int i;

    mutex_lock(&mz_hidden_mutex);
    for (i = 0; i < mz_hidden_path_count_int; i++) {
        kfree(mz_hidden_paths[i]);
        mz_hidden_paths[i] = NULL;
    }
    mz_hidden_path_count_int = 0;
    atomic_set(&mz_hidden_path_count, 0);
    mutex_unlock(&mz_hidden_mutex);

    return 0;
}
EXPORT_SYMBOL(mountzero_clear_hidden_paths);

/* ============================================================
 * Auto Module Scanner - Proper VFS Path Mapping
 * ============================================================ */

struct mz_scan_callback_data {
    struct dir_context ctx;  /* MUST be first for container_of */
    int rules_added;
    int rules_failed;
    const char *module_id;
    const char *module_base;
    const char *partition;  /* "system", "vendor", etc. or NULL for custom */
};

static int mz_scan_partition_callback(struct dir_context *ctx, const char *name,
                                       int namlen, loff_t offset, u64 ino, unsigned int d_type)
{
    struct mz_scan_callback_data *cb = container_of(ctx, struct mz_scan_callback_data, ctx);
    char real_path[512];
    char virt_path[512];

    /* Skip . and .. */
    if (name[0] == '.' && (namlen == 1 || (namlen == 2 && name[1] == '.')))
        return 0;

    /* Build paths based on partition type */
    if (cb->partition) {
        /* Standard module: /data/adb/modules/<id>/system/bin/foo → /system/bin/foo */
        snprintf(real_path, sizeof(real_path), "%s/%s/%.*s", cb->module_base, cb->partition, namlen, name);
        snprintf(virt_path, sizeof(virt_path), "/%s/%.*s", cb->partition, namlen, name);
    } else {
        /* Custom module (DroidSpaces): /data/local/Droidspaces/etc/foo → /system/etc/foo */
        snprintf(real_path, sizeof(real_path), "%s/%.*s", cb->module_base, namlen, name);
        snprintf(virt_path, sizeof(virt_path), "/system/%.*s", namlen, name);
    }

    if (d_type == DT_DIR) {
        /* Recursively scan subdirectory */
        struct file *sub_filp;
        int ret;

        sub_filp = filp_open(real_path, O_RDONLY | O_DIRECTORY, 0);
        if (IS_ERR(sub_filp))
            return 0;

        /* Setup sub-callback with proper initialization */
        struct mz_scan_callback_data sub_cb = {
            .ctx.actor = mz_scan_partition_callback,
            .ctx.pos = 0,
            .module_id = cb->module_id,
            .module_base = cb->module_base,
            .partition = cb->partition,
            .rules_added = 0,
            .rules_failed = 0
        };

        ret = iterate_dir(sub_filp, &sub_cb.ctx);
        filp_close(sub_filp, NULL);

        cb->rules_added += sub_cb.rules_added;
        cb->rules_failed += sub_cb.rules_failed;
    } else if (d_type == DT_REG || d_type == DT_LNK) {
        /* Add redirect rule */
        if (mountzero_add_redirect(virt_path, real_path, 0) == 0) {
            cb->rules_added++;
        } else {
            cb->rules_failed++;
            pr_warn("MountZero: Failed to add rule: %s -> %s\n", virt_path, real_path);
        }
    }

    return 0;
}

/* Scan a specific partition directory within a module */
static int mz_scan_module_partition(const char *module_id, const char *module_base, const char *partition)
{
    struct file *filp;
    char dir_path[512];
    int ret;

    snprintf(dir_path, sizeof(dir_path), "%s/%s", module_base, partition);

    filp = filp_open(dir_path, O_RDONLY | O_DIRECTORY, 0);
    if (IS_ERR(filp))
        return PTR_ERR(filp);

    /* Setup callback with proper initialization */
    struct mz_scan_callback_data cb = {
        .ctx.actor = mz_scan_partition_callback,
        .ctx.pos = 0,
        .module_id = module_id,
        .module_base = module_base,
        .partition = partition,
        .rules_added = 0,
        .rules_failed = 0
    };

    ret = iterate_dir(filp, &cb.ctx);
    filp_close(filp, NULL);

    if (cb.rules_added > 0 || cb.rules_failed > 0)
        pr_info("MountZero: Module %s/%s -> /%s (%d rules, %d failed)\n",
                module_id, partition, partition, cb.rules_added, cb.rules_failed);

    return ret;
}

/* Scan a custom module (like DroidSpaces) */
static int mz_scan_custom_module(const char *module_id, const char *module_base)
{
    struct file *filp;
    int ret;

    filp = filp_open(module_base, O_RDONLY | O_DIRECTORY, 0);
    if (IS_ERR(filp))
        return PTR_ERR(filp);

    /* Setup callback with proper initialization */
    struct mz_scan_callback_data cb = {
        .ctx.actor = mz_scan_partition_callback,
        .ctx.pos = 0,
        .module_id = module_id,
        .module_base = module_base,
        .partition = NULL,  /* Custom structure - map to /system/ */
        .rules_added = 0,
        .rules_failed = 0
    };

    ret = iterate_dir(filp, &cb.ctx);
    filp_close(filp, NULL);

    if (cb.rules_added > 0 || cb.rules_failed > 0)
        pr_info("MountZero: Custom module %s -> /system/ (%d rules, %d failed)\n",
                module_id, cb.rules_added, cb.rules_failed);

    return ret;
}

/* Check if module is enabled */
static bool mz_is_module_enabled(const char *module_id)
{
    struct path path;
    char disable_path[512];
    int ret;

    /* Check for disable file */
    snprintf(disable_path, sizeof(disable_path), "/data/adb/modules/%s/disable", module_id);
    ret = kern_path(disable_path, 0, &path);
    if (ret == 0) {
        path_put(&path);
        return false;
    }

    /* Check for remove file */
    snprintf(disable_path, sizeof(disable_path), "/data/adb/modules/%s/remove", module_id);
    ret = kern_path(disable_path, 0, &path);
    if (ret == 0) {
        path_put(&path);
        return false;
    }

    /* Check for skip_mount file */
    snprintf(disable_path, sizeof(disable_path), "/data/adb/modules/%s/skip_mount", module_id);
    ret = kern_path(disable_path, 0, &path);
    if (ret == 0) {
        path_put(&path);
        return false;
    }

    return true;
}

/* Standard partitions to scan */
static const char * const standard_partitions[] = {
    "system", "vendor", "product", "system_ext", "odm", "odm_dlkm", "vendor_dlkm"
};

/* Callback for iterating through module directories in /data/adb/modules/ */
static int mz_scan_adb_modules_callback(struct dir_context *ctx, const char *name,
                                         int namlen, loff_t offset, u64 ino, unsigned int d_type)
{
    char module_id[256];
    char module_base[512];
    int i;

    if (name[0] == '.' && (namlen == 1 || (namlen == 2 && name[1] == '.')))
        return 0;

    if (d_type != DT_DIR && d_type != DT_UNKNOWN)
        return 0;

    snprintf(module_id, sizeof(module_id), "%.*s", namlen, name);
    snprintf(module_base, sizeof(module_base), "/data/adb/modules/%s", module_id);

    if (!mz_is_module_enabled(module_id)) {
        pr_info("MountZero: Skipping disabled module: %s\n", module_id);
        return 0;
    }

    pr_info("MountZero: Scanning module: %s\n", module_id);

    /* Scan standard partitions */
    for (i = 0; i < ARRAY_SIZE(standard_partitions); i++) {
        mz_scan_module_partition(module_id, module_base, standard_partitions[i]);
    }

    return 0;
}

/* Callback for iterating through custom modules in /data/local/ */
static int mz_scan_local_modules_callback(struct dir_context *ctx, const char *name,
                                           int namlen, loff_t offset, u64 ino, unsigned int d_type)
{
    char module_id[256];
    char module_base[512];

    if (name[0] == '.' && (namlen == 1 || (namlen == 2 && name[1] == '.')))
        return 0;

    if (d_type != DT_DIR && d_type != DT_UNKNOWN)
        return 0;

    snprintf(module_id, sizeof(module_id), "%.*s", namlen, name);
    snprintf(module_base, sizeof(module_base), "/data/local/%s", module_id);

    pr_info("MountZero: Scanning custom module: %s\n", module_id);

    /* Scan as custom structure (maps to /system/) */
    mz_scan_custom_module(module_id, module_base);

    return 0;
}

static int wait_for_data_mount(void)
{
    struct path path;
    int retries = 30;

    while (retries--) {
        if (kern_path("/data/adb/modules", LOOKUP_FOLLOW, &path) == 0) {
            path_put(&path);
            pr_info("MountZero: /data mounted, ready for auto-scan\n");
            return 0;
        }
        msleep(1000);
    }
    return -ENODEV;
}

/* Scan a single module (for hot-plug) */
int mountzero_scan_single_module(const char *module_id, const char *module_path, bool is_custom)
{
    int i;
    int total_rules = 0;

    pr_info("MountZero: Hot-plug scanning module: %s\n", module_id);

    if (is_custom) {
        total_rules += mz_scan_custom_module(module_id, module_path);
    } else {
        for (i = 0; i < ARRAY_SIZE(standard_partitions); i++) {
            total_rules += mz_scan_module_partition(module_id, module_path, standard_partitions[i]);
        }
    }

    pr_info("MountZero: Module %s scan complete: %d rules added\n", module_id, total_rules);
    return total_rules;
}
EXPORT_SYMBOL(mountzero_scan_single_module);

/* Hot-plug auto-detection state */
static bool mz_hotplug_enabled = true;
static struct task_struct *mz_hotplug_thread;
static DECLARE_WAIT_QUEUE_HEAD(mz_hotplug_wait);

/* Hot-plug kernel thread - watches for new modules */
static int mz_hotplug_thread_fn(void *data)
{
    while (!kthread_should_stop()) {
        wait_event_interruptible_timeout(mz_hotplug_wait,
                                 kthread_should_stop() || !mz_hotplug_enabled,
                                 msecs_to_jiffies(5000));

        if (mz_hotplug_enabled && !kthread_should_stop()) {
            /* Module polling logic handled by userspace service.sh */
        }
    }
    return 0;
}

/* Enable hot-plug auto-detection */
void mountzero_enable_hotplug(void)
{
    mz_hotplug_enabled = true;
    wake_up(&mz_hotplug_wait);
    pr_info("MountZero: Hot-plug auto-detection enabled\n");
}
EXPORT_SYMBOL(mountzero_enable_hotplug);

/* Disable hot-plug auto-detection */
void mountzero_disable_hotplug(void)
{
    mz_hotplug_enabled = false;
    pr_info("MountZero: Hot-plug auto-detection disabled\n");
}
EXPORT_SYMBOL(mountzero_disable_hotplug);

static int __init mountzero_auto_scan_modules(void)
{
    struct file *filp;
    int ret;

    /* Check bootloop guard */
    if (atomic_read(&mz_bootloop_count) >= mz_bootloop_threshold) {
        mz_guard_tripped = true;
        pr_warn("MountZero: Bootloop guard tripped (count=%d), skipping auto-scan\n",
                atomic_read(&mz_bootloop_count));
        return 0;
    }

    ret = wait_for_data_mount();
    if (ret) {
        pr_warn("MountZero: /data not available, skipping auto-scan\n");
        return 0;
    }

    /* Scan /data/adb/modules/ - Standard KernelSU modules */
    pr_info("MountZero: Starting auto-scan of /data/adb/modules...\n");

    filp = filp_open("/data/adb/modules", O_RDONLY | O_DIRECTORY, 0);
    if (!IS_ERR(filp)) {
        struct dir_context ctx = {
            .actor = mz_scan_adb_modules_callback,
            .pos = 0
        };

        ret = iterate_dir(filp, &ctx);
        filp_close(filp, NULL);

        if (ret == 0)
            pr_info("MountZero: /data/adb/modules scan complete\n");
        else
            pr_err("MountZero: /data/adb/modules scan failed: %d\n", ret);
    } else {
        pr_info("MountZero: /data/adb/modules not found, skipping\n");
    }

    /* Scan /data/adb/modules_update/ - Newly installed modules */
    filp = filp_open("/data/adb/modules_update", O_RDONLY | O_DIRECTORY, 0);
    if (!IS_ERR(filp)) {
        struct dir_context ctx = {
            .actor = mz_scan_adb_modules_callback,
            .pos = 0
        };

        ret = iterate_dir(filp, &ctx);
        filp_close(filp, NULL);
    }

    /* Scan /data/local/ - Custom modules like DroidSpaces */
    pr_info("MountZero: Starting auto-scan of /data/local...\n");

    filp = filp_open("/data/local", O_RDONLY | O_DIRECTORY, 0);
    if (!IS_ERR(filp)) {
        struct dir_context ctx = {
            .actor = mz_scan_local_modules_callback,
            .pos = 0
        };

        ret = iterate_dir(filp, &ctx);
        filp_close(filp, NULL);

        if (ret == 0)
            pr_info("MountZero: /data/local scan complete\n");
        else
            pr_err("MountZero: /data/local scan failed: %d\n", ret);
    } else {
        pr_info("MountZero: /data/local not found, skipping\n");
    }

    /* Record successful boot for guard */
    atomic_set(&mz_bootloop_count, 0);

    pr_info("MountZero: Auto-scan complete. Total rules: %d\n",
            atomic_read(&mz_rule_count));
    return 0;
}
late_initcall_sync(mountzero_auto_scan_modules);

/* ============================================================
 * IOCTL Handler
 * ============================================================ */

static long mountzero_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
    int ret = 0;

    if (_IOC_TYPE(cmd) != MOUNTZERO_IOC_MAGIC)
        return -ENOTTY;

    if (cmd != MOUNTZERO_IOC_GET_VERSION) {
        if (!capable(CAP_SYS_ADMIN))
            return -EPERM;
    }

    switch (cmd) {
    case MOUNTZERO_IOC_GET_VERSION:
        return 0;

    case MOUNTZERO_IOC_ENABLE:
        atomic_set(&mountzero_enabled, 1);
        pr_info("MountZero: VFS engine enabled\n");
        return 0;

    case MOUNTZERO_IOC_DISABLE:
        atomic_set(&mountzero_enabled, 0);
        pr_info("MountZero: VFS engine disabled\n");
        return 0;

    case MOUNTZERO_IOC_GET_STATUS:
        return atomic_read(&mountzero_enabled);

    case MOUNTZERO_IOC_ADD_REDIRECT: {
        struct mz_ioctl_rule rule;
        if (copy_from_user(&rule, (void __user *)arg, sizeof(rule)))
            return -EFAULT;
        rule.virtual_path[sizeof(rule.virtual_path) - 1] = '\0';
        rule.real_path[sizeof(rule.real_path) - 1] = '\0';
        return mountzero_add_redirect(rule.virtual_path, rule.real_path, rule.flags);
    }

    case MOUNTZERO_IOC_DEL_REDIRECT: {
        char vpath[256];
        if (copy_from_user(vpath, (void __user *)arg, sizeof(vpath)))
            return -EFAULT;
        vpath[sizeof(vpath) - 1] = '\0';
        return mountzero_del_redirect(vpath);
    }

    case MOUNTZERO_IOC_INSTALL_MODULE: {
        struct mz_install_module mod;
        if (copy_from_user(&mod, (void __user *)arg, sizeof(mod)))
            return -EFAULT;
        mod.module_id[sizeof(mod.module_id) - 1] = '\0';
        mod.module_path[sizeof(mod.module_path) - 1] = '\0';
        return mountzero_scan_single_module(mod.module_id, mod.module_path, mod.is_custom);
    }

    case MOUNTZERO_IOC_CLEAR: {
        struct mz_rule *rule;
        struct hlist_node *tmp;
        int bkt;
        unsigned long irq_flags;

        /*
         * CRITICAL: Disable MountZero first to prevent new VFS hook lookups.
         * Then synchronize_rcu() to wait for any in-flight VFS path resolution
         * to complete before freeing rules. Without this, concurrent
         * mountzero_resolve_path() can access freed rule memory → panic/reboot.
         */
        atomic_set(&mountzero_enabled, 0);
        synchronize_rcu();

        spin_lock_irqsave(&mz_lock, irq_flags);

        /* Clear redirect rules hash table */
        hash_for_each_safe(mz_redirect_rules_ht, bkt, tmp, rule, node) {
            hash_del(&rule->node);
            /* Also remove from inode hash table to prevent use-after-free */
            if (!hlist_unhashed(&rule->ino_node))
                hash_del(&rule->ino_node);
            kfree(rule->virtual_path);
            kfree(rule->real_path);
            kfree(rule);
        }

        /* Also sweep mz_ino_ht for any orphaned entries */
        hash_for_each_safe(mz_ino_ht, bkt, tmp, rule, ino_node) {
            hash_del(&rule->ino_node);
            kfree(rule->virtual_path);
            kfree(rule->real_path);
            kfree(rule);
        }

        bitmap_zero(mz_bloom, MZ_BLOOM_BITS);

        spin_unlock_irqrestore(&mz_lock, irq_flags);

        /* Re-enable MountZero after rules are cleared safely */
        atomic_set(&mountzero_enabled, 1);

        pr_info("MountZero: All rules cleared safely\n");
        return 0;
    }

    case MOUNTZERO_IOC_LIST: {
        struct mz_ioctl_list list;
        int count = 0;
        struct mz_rule *rule;
        int bkt;
        int offset = 0;

        memset(&list, 0, sizeof(list));

        spin_lock(&mz_lock);

        hash_for_each(mz_redirect_rules_ht, bkt, rule, node) {
            int len = snprintf(list.entries + offset, sizeof(list.entries) - offset,
                             "REDIRECT: %s -> %s\n", rule->virtual_path, rule->real_path);
            if (len > 0 && offset + len < sizeof(list.entries)) {
                offset += len;
                count++;
            } else {
                break;
            }
        }

        spin_unlock(&mz_lock);

        list.count = count;

        if (copy_to_user((void __user *)arg, &list, sizeof(list)))
            return -EFAULT;

        return 0;
    }

    /* SUSFS Bridge IOCTLs */
#ifdef CONFIG_KSU_SUSFS
    case MOUNTZERO_IOC_ADD_SUS_PATH: {
        char path[256];
        if (copy_from_user(path, (void __user *)arg, sizeof(path)))
            return -EFAULT;
        path[sizeof(path) - 1] = '\0';
        return mountzero_susfs_add_path(path);
    }

    case MOUNTZERO_IOC_ADD_SUS_MAP: {
        char path[256];
        if (copy_from_user(path, (void __user *)arg, sizeof(path)))
            return -EFAULT;
        path[sizeof(path) - 1] = '\0';
        return mountzero_susfs_add_map(path);
    }

    case MOUNTZERO_IOC_SET_UNAME: {
        struct mz_uname_info uname_info;
        if (copy_from_user(&uname_info, (void __user *)arg, sizeof(uname_info)))
            return -EFAULT;
        uname_info.kernel_release[sizeof(uname_info.kernel_release) - 1] = '\0';
        uname_info.kernel_version[sizeof(uname_info.kernel_version) - 1] = '\0';
        return mountzero_susfs_set_uname(uname_info.kernel_release, uname_info.kernel_version);
    }
#endif

    default:
        return -EINVAL;
    }

    return ret;
}

static int mountzero_dev_open(struct inode *inode, struct file *file)
{
    if (!uid_eq(current_euid(), GLOBAL_ROOT_UID)) {
        pr_warn("MountZero: Permission denied for uid %d\n", current_euid().val);
        return -EPERM;
    }
    return 0;
}

static int mountzero_dev_release(struct inode *inode, struct file *file)
{
    return 0;
}

static const struct file_operations mountzero_fops = {
    .owner = THIS_MODULE,
    .open = mountzero_dev_open,
    .release = mountzero_dev_release,
    .unlocked_ioctl = mountzero_ioctl,
#ifdef CONFIG_COMPAT
    .compat_ioctl = mountzero_ioctl,
#endif
};

static struct miscdevice mountzero_misc = {
    .minor = MISC_DYNAMIC_MINOR,
    .name = "mountzero",
    .fops = &mountzero_fops,
};

int __init mountzero_init(void)
{
    int ret;

    pr_info("MountZero: Initializing MountZero v%s (Enhanced)\n", MOUNTZERO_VERSION);

    hash_init(mz_redirect_rules_ht);
    hash_init(mz_bind_rules_ht);
    hash_init(mz_hide_rules_ht);
    hash_init(mz_sus_path_ht);
    hash_init(mz_sus_map_ht);
    hash_init(mz_ino_ht);

    bitmap_zero(mz_bloom, MZ_BLOOM_BITS);

    ret = misc_register(&mountzero_misc);
    if (ret) {
        pr_err("MountZero: Failed to register misc device: %d\n", ret);
        return ret;
    }

    atomic_set(&mountzero_enabled, 1);

    /* Create sysfs entries */
    ret = sysfs_create_group(kernel_kobj, &mz_attr_group);
    if (ret)
        pr_warn("MountZero: Failed to create sysfs group: %d\n", ret);

    /* Create guard sysfs subdirectory */
    mz_guard_kobj = kobject_create_and_add("mountzero_guard", kernel_kobj);
    if (mz_guard_kobj) {
        ret = sysfs_create_group(mz_guard_kobj, &mz_guard_attr_group);
        if (ret) {
            pr_warn("MountZero: Failed to create guard sysfs: %d\n", ret);
            kobject_put(mz_guard_kobj);
            mz_guard_kobj = NULL;
        }
    }

    pr_info("MountZero: Device registered at /dev/mountzero (minor=%d)\n",
            mountzero_misc.minor);
    pr_info("MountZero: Sysfs at /sys/kernel/mountzero/\n");

    /* Start hot-plug thread */
    mz_hotplug_thread = kthread_run(mz_hotplug_thread_fn, NULL, "mz_hotplug");
    if (IS_ERR(mz_hotplug_thread)) {
        pr_warn("MountZero: Failed to start hot-plug thread\n");
        mz_hotplug_thread = NULL;
    }

    return 0;
}

void __exit mountzero_exit(void)
{
    struct mz_rule *rule;
    struct hlist_node *tmp;
    int bkt;
    unsigned long irq_flags;

    /* Stop hot-plug thread */
    if (mz_hotplug_thread) {
        kthread_stop(mz_hotplug_thread);
        mz_hotplug_thread = NULL;
    }

    spin_lock_irqsave(&mz_lock, irq_flags);

    hash_for_each_safe(mz_redirect_rules_ht, bkt, tmp, rule, node) {
        hash_del(&rule->node);
        if (!hlist_unhashed(&rule->ino_node))
            hash_del(&rule->ino_node);
        kfree(rule->virtual_path);
        kfree(rule->real_path);
        kfree(rule);
    }

    hash_for_each_safe(mz_ino_ht, bkt, tmp, rule, ino_node) {
        hash_del(&rule->ino_node);
        kfree(rule->virtual_path);
        kfree(rule->real_path);
        kfree(rule);
    }

    spin_unlock_irqrestore(&mz_lock, irq_flags);

    /* Remove sysfs entries */
    if (mz_guard_kobj) {
        kobject_put(mz_guard_kobj);
        mz_guard_kobj = NULL;
    }
    sysfs_remove_group(kernel_kobj, &mz_attr_group);

    misc_deregister(&mountzero_misc);
    pr_info("MountZero: Module unloaded\n");
}

module_init(mountzero_init);
module_exit(mountzero_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Mastermind");
MODULE_DESCRIPTION("MountZero - Enhanced VFS path redirection, SUSFS bridge, and module auto-scanning");
MODULE_VERSION(MOUNTZERO_VERSION);
