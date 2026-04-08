/*
 * MountZero - Public Header
 *
 * IOCTL interface and function declarations for userspace tools.
 * Enhanced v2.0.0 - Full SUSFS bridge, UID exclusion, hidden paths.
 */

#ifndef __LINUX_MOUNTZERO_H
#define __LINUX_MOUNTZERO_H

#include <linux/ioctl.h>
#include <linux/types.h>
#include <linux/uidgid.h>

/* IOCTL Magic Number */
#define MOUNTZERO_IOC_MAGIC 'Z'

/* IOCTL Commands - Core */
#define MOUNTZERO_IOC_GET_VERSION    _IOR(MOUNTZERO_IOC_MAGIC, 1, int)
#define MOUNTZERO_IOC_ENABLE         _IO(MOUNTZERO_IOC_MAGIC, 2)
#define MOUNTZERO_IOC_DISABLE        _IO(MOUNTZERO_IOC_MAGIC, 3)
#define MOUNTZERO_IOC_GET_STATUS     _IOR(MOUNTZERO_IOC_MAGIC, 4, int)

#define MOUNTZERO_IOC_ADD_REDIRECT   _IOW(MOUNTZERO_IOC_MAGIC, 10, struct mz_ioctl_rule)
#define MOUNTZERO_IOC_DEL_REDIRECT   _IOW(MOUNTZERO_IOC_MAGIC, 11, char*)

#define MOUNTZERO_IOC_ADD_BIND       _IOW(MOUNTZERO_IOC_MAGIC, 20, struct mz_ioctl_bind)
#define MOUNTZERO_IOC_DEL_BIND       _IOW(MOUNTZERO_IOC_MAGIC, 21, char*)

#define MOUNTZERO_IOC_ADD_SYMLINK    _IOW(MOUNTZERO_IOC_MAGIC, 30, struct mz_ioctl_symlink)
#define MOUNTZERO_IOC_ADD_WHITEOUT   _IOW(MOUNTZERO_IOC_MAGIC, 40, char*)

/* IOCTL Commands - SUSFS Bridge */
#define MOUNTZERO_IOC_ADD_SUS_PATH   _IOW(MOUNTZERO_IOC_MAGIC, 50, char*)
#define MOUNTZERO_IOC_ADD_SUS_MAP    _IOW(MOUNTZERO_IOC_MAGIC, 51, char*)
#define MOUNTZERO_IOC_SET_UNAME      _IOW(MOUNTZERO_IOC_MAGIC, 60, struct mz_uname_info)

/* IOCTL Commands - Module Management */
#define MOUNTZERO_IOC_INSTALL_MODULE _IOW(MOUNTZERO_IOC_MAGIC, 70, struct mz_install_module)

/* IOCTL Commands - UID Exclusion */
#define MOUNTZERO_IOC_BLOCK_UID      _IOW(MOUNTZERO_IOC_MAGIC, 80, uid_t)
#define MOUNTZERO_IOC_UNBLOCK_UID    _IOW(MOUNTZERO_IOC_MAGIC, 81, uid_t)

/* IOCTL Commands - Hidden Paths */
#define MOUNTZERO_IOC_ADD_HIDDEN_PATH _IOW(MOUNTZERO_IOC_MAGIC, 90, char*)
#define MOUNTZERO_IOC_CLEAR_HIDDEN    _IO(MOUNTZERO_IOC_MAGIC, 91)

/* IOCTL Commands - Management */
#define MOUNTZERO_IOC_CLEAR          _IO(MOUNTZERO_IOC_MAGIC, 100)
#define MOUNTZERO_IOC_LIST           _IOR(MOUNTZERO_IOC_MAGIC, 101, struct mz_ioctl_list)
#define MOUNTZERO_IOC_REFRESH        _IO(MOUNTZERO_IOC_MAGIC, 102)

/* Data Structures */

struct mz_ioctl_rule {
    char virtual_path[256];
    char real_path[256];
    unsigned int flags;
};

struct mz_ioctl_bind {
    char source[256];
    char target[256];
    unsigned int flags;
};

struct mz_ioctl_symlink {
    char target[256];
    char link[256];
};

struct mz_uname_info {
    char kernel_release[64];
    char kernel_version[64];
};

struct mz_install_module {
    char module_id[256];
    char module_path[512];
    int is_custom;  /* 0 = standard KernelSU module, 1 = custom (DroidSpaces) */
};

struct mz_ioctl_list {
    char entries[4096];
    int count;
};

/* Function Declarations */

#ifdef __KERNEL__

#include <linux/mountzero_def.h>

/* Core functions */
int mountzero_init(void);
void mountzero_exit(void);

/* Path resolution */
bool mountzero_should_redirect(const char *path);
char *mountzero_resolve_path(const char *path);
char *mountzero_get_static_vpath(struct inode *inode);

/* Rule management */
int mountzero_add_redirect(const char *virtual_path, const char *real_path, unsigned int flags);
int mountzero_del_redirect(const char *virtual_path);

/* Hot-plug module installation */
int mountzero_install_module(const char *module_id, const char *module_path, bool is_custom);
int mountzero_scan_single_module(const char *module_id, const char *module_path, bool is_custom);

/* SUSFS Bridge */
int mountzero_susfs_add_path(const char *path);
int mountzero_susfs_add_path_loop(const char *path);
int mountzero_susfs_add_kstat(const char *path);
int mountzero_susfs_update_kstat(const char *path);
int mountzero_susfs_add_map(const char *path);
int mountzero_susfs_set_uname(const char *release, const char *version);
int mountzero_susfs_set_cmdline(const char *path);
int mountzero_susfs_hide_mounts(bool enable);
int mountzero_susfs_enable_log(bool enable);
int mountzero_susfs_enable_avc_log_spoofing(bool enable);
int mountzero_susfs_get_version(char *buf, size_t len);
int mountzero_susfs_get_features(char *buf, size_t len);

/* UID Exclusion */
int mountzero_block_uid(uid_t uid);
int mountzero_unblock_uid(uid_t uid);
bool mountzero_is_uid_excluded(uid_t uid);

/* Hidden Paths */
int mountzero_add_hidden_path(const char *path);
int mountzero_clear_hidden_paths(void);

/* Hot-plug */
void mountzero_enable_hotplug(void);
void mountzero_disable_hotplug(void);

/* VFS hooks - declared in mountzero_vfs.h */

#endif /* __KERNEL__ */

#endif /* __LINUX_MOUNTZERO_H */
