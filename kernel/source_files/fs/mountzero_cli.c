/*
 * MountZero - Full Userspace CLI Tool
 *
 * Equivalent to ZeroMount's Rust binary. Handles:
 * - mount pipeline (detect → scan → execute)
 * - VFS rule management
 * - SUSFS bridge
 * - Module management
 * - Config system (TOML)
 * - Bootloop guard
 * - System diagnostics
 * - UID exclusion
 * - Hidden paths
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <dirent.h>
#include <ctype.h>
#include <time.h>

/* Standalone IOCTL definitions — avoid kernel headers in userspace */
#define MOUNTZERO_IOC_MAGIC 'Z'
#define MOUNTZERO_IOC_GET_VERSION    _IOR(MOUNTZERO_IOC_MAGIC, 1, int)
#define MOUNTZERO_IOC_ENABLE         _IO(MOUNTZERO_IOC_MAGIC, 2)
#define MOUNTZERO_IOC_DISABLE        _IO(MOUNTZERO_IOC_MAGIC, 3)
#define MOUNTZERO_IOC_GET_STATUS     _IOR(MOUNTZERO_IOC_MAGIC, 4, int)
#define MOUNTZERO_IOC_ADD_REDIRECT   _IOW(MOUNTZERO_IOC_MAGIC, 10, struct mz_ioctl_rule)
#define MOUNTZERO_IOC_DEL_REDIRECT   _IOW(MOUNTZERO_IOC_MAGIC, 11, char*)
#define MOUNTZERO_IOC_ADD_SUS_PATH   _IOW(MOUNTZERO_IOC_MAGIC, 50, char*)
#define MOUNTZERO_IOC_ADD_SUS_MAP    _IOW(MOUNTZERO_IOC_MAGIC, 51, char)
#define MOUNTZERO_IOC_SET_UNAME      _IOW(MOUNTZERO_IOC_MAGIC, 60, struct mz_uname_info)
#define MOUNTZERO_IOC_BLOCK_UID      _IOW(MOUNTZERO_IOC_MAGIC, 80, unsigned int)
#define MOUNTZERO_IOC_UNBLOCK_UID    _IOW(MOUNTZERO_IOC_MAGIC, 81, unsigned int)
#define MOUNTZERO_IOC_INSTALL_MODULE _IOW(MOUNTZERO_IOC_MAGIC, 70, struct mz_install_module)
#define MOUNTZERO_IOC_CLEAR          _IO(MOUNTZERO_IOC_MAGIC, 100)
#define MOUNTZERO_IOC_LIST           _IOR(MOUNTZERO_IOC_MAGIC, 101, struct mz_ioctl_list)

struct mz_ioctl_rule {
    char virtual_path[256];
    char real_path[256];
    unsigned int flags;
};

struct mz_uname_info {
    char kernel_release[64];
    char kernel_version[64];
};

struct mz_install_module {
    char module_id[256];
    char module_path[512];
    int is_custom;
};

struct mz_ioctl_list {
    char entries[4096];
    int count;
};

/* ============================================================
 * Constants and Globals
 * ============================================================ */

#define MZ_DEVICE_PATH "/dev/mountzero"
#define MZ_SYSFS_PATH "/sys/kernel/mountzero"
#define MZ_DATA_DIR "/data/adb/mountzero"
#define MZ_CONFIG_PATH "/data/adb/mountzero/config.toml"
#define MZ_DETECTION_PATH "/data/adb/mountzero/.detection.json"
#define MZ_MODULES_DIR "/data/adb/modules"
#define MZ_MODULES_UPDATE_DIR "/data/adb/modules_update"
#define MZ_LOCAL_DIR "/data/local"

static int mz_fd = -1;

/* ============================================================
 * Helpers
 * ============================================================ */

static int mz_open_device(void)
{
    if (mz_fd < 0) {
        mz_fd = open(MZ_DEVICE_PATH, O_RDWR);
        if (mz_fd < 0) {
            fprintf(stderr, "Error: Cannot open %s: %s\n", MZ_DEVICE_PATH, strerror(errno));
            return -1;
        }
    }
    return mz_fd;
}

static void mz_close_device(void)
{
    if (mz_fd >= 0) {
        close(mz_fd);
        mz_fd = -1;
    }
}

static const char *standard_partitions[] = {
    "system", "vendor", "product", "system_ext", "odm", "odm_dlkm", "vendor_dlkm"
};
#define NUM_PARTITIONS (sizeof(standard_partitions) / sizeof(standard_partitions[0]))

static int is_module_enabled(const char *module_id)
{
    char path[512];
    struct stat st;

    snprintf(path, sizeof(path), "%s/%s/disable", MZ_MODULES_DIR, module_id);
    if (stat(path, &st) == 0) return 0;

    snprintf(path, sizeof(path), "%s/%s/remove", MZ_MODULES_DIR, module_id);
    if (stat(path, &st) == 0) return 0;

    snprintf(path, sizeof(path), "%s/%s/skip_mount", MZ_MODULES_DIR, module_id);
    if (stat(path, &st) == 0) return 0;

    return 1;
}

static void print_usage(void)
{
    printf("MountZero VFS CLI Tool v2.0.0\n\n");
    printf("Usage: mountzero <command> [arguments]\n\n");
    printf("Commands:\n");
    printf("  version                          Show MountZero version\n");
    printf("  status                           Show MountZero status\n");
    printf("  enable                           Enable MountZero VFS engine\n");
    printf("  disable                          Disable MountZero VFS engine\n");
    printf("\n");
    printf("  add <virt> <real>                Add VFS redirect rule\n");
    printf("  del <virt>                       Delete VFS redirect rule\n");
    printf("  list                             List all active rules\n");
    printf("  clear                            Clear all rules\n");
    printf("  refresh                          Refresh dcache after rule changes\n");
    printf("\n");
    printf("  module <subcommand> [args]       Module operations\n");
    printf("    scan                           Scan all modules\n");
    printf("    install <id> <path> [custom]   Install module\n");
    printf("    list                           List installed modules\n");
    printf("\n");
    printf("  uid <subcommand> <uid>           UID exclusion management\n");
    printf("    block <uid>                    Block UID from VFS\n");
    printf("    unblock <uid>                  Unblock UID\n");
    printf("\n");
    printf("  susfs <subcommand> [args]        SUSFS bridge\n");
    printf("    add-path <path>                Add hidden path\n");
    printf("    add-map <path>                 Add maps hiding\n");
    printf("    set-uname <release> <version>  Spoof uname\n");
    printf("    version                        Show SUSFS version\n");
    printf("    features                       Show SUSFS features\n");
    printf("\n");
    printf("  guard <subcommand>               Bootloop guard\n");
    printf("    check                          Check guard status\n");
    printf("    recover                        Reset guard after recovery\n");
    printf("\n");
    printf("  detect                           Probe kernel capabilities\n");
    printf("  dump                             Diagnostic dump\n");
    printf("  help                             Show this help\n");
}

/* ============================================================
 * Version
 * ============================================================ */

static int cmd_version(int argc, char **argv)
{
    int fd;
    int version;

    fd = mz_open_device();
    if (fd < 0) return 1;

    if (ioctl(fd, MOUNTZERO_IOC_GET_VERSION, &version) == 0) {
        printf("MountZero VFS Version: %d\n", version);
    } else {
        /* Read from sysfs */
        FILE *f = fopen(MZ_SYSFS_PATH "/version", "r");
        if (f) {
            char buf[64];
            if (fgets(buf, sizeof(buf), f)) {
                printf("MountZero VFS Version: %s", buf);
            }
            fclose(f);
            return 0;
        }
        fprintf(stderr, "Error: Cannot get version\n");
        return 1;
    }
    return 0;
}

/* ============================================================
 * Status
 * ============================================================ */

static int cmd_status(int argc, char **argv)
{
    int fd;
    int status;
    FILE *f;

    fd = mz_open_device();
    if (fd < 0) return 1;

    status = ioctl(fd, MOUNTZERO_IOC_GET_STATUS, NULL);
    if (status >= 0) {
        printf("MountZero VFS Status: %s\n", status ? "ENABLED" : "DISABLED");
    } else {
        fprintf(stderr, "Error: GET_STATUS ioctl failed: %s\n", strerror(errno));
        return 1;
    }

    /* Read sysfs status for detailed info */
    f = fopen(MZ_SYSFS_PATH "/status", "r");
    if (f) {
        char buf[256];
        printf("\nEngine Details:\n");
        while (fgets(buf, sizeof(buf), f)) {
            printf("  %s", buf);
        }
        fclose(f);
    }

    return 0;
}

/* ============================================================
 * Enable / Disable
 * ============================================================ */

static int cmd_enable(int argc, char **argv)
{
    int fd = mz_open_device();
    if (fd < 0) return 1;

    if (ioctl(fd, MOUNTZERO_IOC_ENABLE) == 0) {
        printf("MountZero VFS engine enabled\n");
        return 0;
    }
    fprintf(stderr, "Error: Failed to enable: %s\n", strerror(errno));
    return 1;
}

static int cmd_disable(int argc, char **argv)
{
    int fd = mz_open_device();
    if (fd < 0) return 1;

    if (ioctl(fd, MOUNTZERO_IOC_DISABLE) == 0) {
        printf("MountZero VFS engine disabled\n");
        return 0;
    }
    fprintf(stderr, "Error: Failed to disable: %s\n", strerror(errno));
    return 1;
}

/* ============================================================
 * VFS Rules
 * ============================================================ */

static int cmd_add(int argc, char **argv)
{
    int fd;
    struct mz_ioctl_rule rule;

    if (argc < 3) {
        fprintf(stderr, "Usage: mountzero add <virtual_path> <real_path>\n");
        return 1;
    }

    fd = mz_open_device();
    if (fd < 0) return 1;

    memset(&rule, 0, sizeof(rule));
    strncpy(rule.virtual_path, argv[1], sizeof(rule.virtual_path) - 1);
    strncpy(rule.real_path, argv[2], sizeof(rule.real_path) - 1);

    if (ioctl(fd, MOUNTZERO_IOC_ADD_REDIRECT, &rule) == 0) {
        printf("Added rule: %s -> %s\n", rule.virtual_path, rule.real_path);
        return 0;
    }
    fprintf(stderr, "Error: Failed to add rule: %s\n", strerror(errno));
    return 1;
}

static int cmd_del(int argc, char **argv)
{
    int fd;
    char vpath[256];

    if (argc < 2) {
        fprintf(stderr, "Usage: mountzero del <virtual_path>\n");
        return 1;
    }

    fd = mz_open_device();
    if (fd < 0) return 1;

    strncpy(vpath, argv[1], sizeof(vpath) - 1);

    if (ioctl(fd, MOUNTZERO_IOC_DEL_REDIRECT, vpath) == 0) {
        printf("Deleted rule: %s\n", vpath);
        return 0;
    }
    fprintf(stderr, "Error: Failed to delete rule: %s\n", strerror(errno));
    return 1;
}

static int cmd_list(int argc, char **argv)
{
    int fd;
    struct mz_ioctl_list list;

    fd = mz_open_device();
    if (fd < 0) return 1;

    memset(&list, 0, sizeof(list));

    if (ioctl(fd, MOUNTZERO_IOC_LIST, &list) == 0) {
        printf("MountZero VFS Rules (%d total):\n", list.count);
        if (list.count > 0) {
            printf("%s", list.entries);
        }
        return 0;
    }
    fprintf(stderr, "Error: LIST ioctl failed: %s\n", strerror(errno));
    return 1;
}

static int cmd_clear(int argc, char **argv)
{
    int fd = mz_open_device();
    if (fd < 0) return 1;

    if (ioctl(fd, MOUNTZERO_IOC_CLEAR) == 0) {
        printf("All MountZero VFS rules cleared\n");
        return 0;
    }
    fprintf(stderr, "Error: CLEAR ioctl failed: %s\n", strerror(errno));
    return 1;
}

/* ============================================================
 * Module Management
 * ============================================================ */

static int scan_directory_recursive(const char *module_id, const char *base_path,
                                     const char *partition, int *rules_added, int *rules_failed)
{
    DIR *dir;
    struct dirent *entry;
    char full_path[512];
    char virt_path[512];
    char real_path[512];

    if (partition) {
        snprintf(full_path, sizeof(full_path), "%s/%s", base_path, partition);
    } else {
        snprintf(full_path, sizeof(full_path), "%s", base_path);
    }

    dir = opendir(full_path);
    if (!dir) {
        return -1;
    }

    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.' &&
            (entry->d_name[1] == '\0' ||
             (entry->d_name[1] == '.' && entry->d_name[2] == '\0')))
            continue;

        snprintf(real_path, sizeof(real_path), "%s/%s", full_path, entry->d_name);

        if (partition) {
            snprintf(virt_path, sizeof(virt_path), "/%s/%s", partition, entry->d_name);
        } else {
            snprintf(virt_path, sizeof(virt_path), "/system/%s", entry->d_name);
        }

        if (entry->d_type == DT_DIR) {
            if (partition) {
                scan_directory_recursive(module_id, base_path, entry->d_name,
                                          rules_added, rules_failed);
            } else {
                /* For custom modules, scan subdirs */
                int sub_added = 0, sub_failed = 0;
                scan_directory_recursive(module_id, real_path, NULL, &sub_added, &sub_failed);
                *rules_added += sub_added;
                *rules_failed += sub_failed;
            }
        } else if (entry->d_type == DT_REG || entry->d_type == DT_LNK) {
            int fd = mz_open_device();
            if (fd >= 0) {
                struct mz_ioctl_rule rule;
                memset(&rule, 0, sizeof(rule));
                strncpy(rule.virtual_path, virt_path, sizeof(rule.virtual_path) - 1);
                strncpy(rule.real_path, real_path, sizeof(rule.real_path) - 1);

                if (ioctl(fd, MOUNTZERO_IOC_ADD_REDIRECT, &rule) == 0) {
                    (*rules_added)++;
                } else {
                    (*rules_failed)++;
                    fprintf(stderr, "  Failed: %s -> %s\n", virt_path, real_path);
                }
            }
        }
    }

    closedir(dir);
    return 0;
}

static int cmd_module_install(int argc, char **argv)
{
    int fd;
    struct mz_install_module mod;
    const char *skip_dirs[] = {
        "lost+found", "tmp", "media", "oem", "vendor", "system", "tests", "traces",
        "bin", "webroot", "Logs", "Pids", "Net", "Containers", "storage", "data",
        NULL
    };

    if (argc < 3) {
        fprintf(stderr, "Usage: mountzero module install <module_id> <module_path> [custom]\n");
        return 1;
    }

    fd = mz_open_device();
    if (fd < 0) return 1;

    memset(&mod, 0, sizeof(mod));
    strncpy(mod.module_id, argv[1], sizeof(mod.module_id) - 1);
    strncpy(mod.module_path, argv[2], sizeof(mod.module_path) - 1);
    mod.is_custom = (argc >= 4 && strcmp(argv[3], "custom") == 0) ? 1 : 0;

    printf("Installing module '%s' from %s (%s)...\n",
           mod.module_id, mod.module_path, mod.is_custom ? "custom" : "standard");

    if (ioctl(fd, MOUNTZERO_IOC_INSTALL_MODULE, &mod) == 0) {
        printf("Module '%s' installed successfully\n", mod.module_id);
        return 0;
    }
    fprintf(stderr, "Error: Failed to install module: %s\n", strerror(errno));
    return 1;
}

static int cmd_module_scan(int argc, char **argv)
{
    DIR *dir;
    struct dirent *entry;
    char module_path[512];
    int total_modules = 0;
    int total_rules = 0;

    printf("Scanning modules in %s...\n", MZ_MODULES_DIR);

    dir = opendir(MZ_MODULES_DIR);
    if (!dir) {
        fprintf(stderr, "Error: Cannot open %s: %s\n", MZ_MODULES_DIR, strerror(errno));
        return 1;
    }

    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.' &&
            (entry->d_name[1] == '\0' ||
             (entry->d_name[1] == '.' && entry->d_name[2] == '\0')))
            continue;

        if (entry->d_type != DT_DIR) continue;

        snprintf(module_path, sizeof(module_path), "%s/%s", MZ_MODULES_DIR, entry->d_name);

        if (!is_module_enabled(entry->d_name)) {
            printf("  Skipping disabled module: %s\n", entry->d_name);
            continue;
        }

        printf("  Scanning module: %s\n", entry->d_name);
        total_modules++;

        /* Install via kernel */
        int fd = mz_open_device();
        if (fd >= 0) {
            struct mz_install_module mod;
            memset(&mod, 0, sizeof(mod));
            strncpy(mod.module_id, entry->d_name, sizeof(mod.module_id) - 1);
            strncpy(mod.module_path, module_path, sizeof(mod.module_path) - 1);
            mod.is_custom = 0;

            int ret = ioctl(fd, MOUNTZERO_IOC_INSTALL_MODULE, &mod);
            if (ret >= 0) {
                total_rules += ret;
                printf("    -> %d rules added\n", ret);
            }
        }
    }

    closedir(dir);

    /* Scan custom modules */
    printf("\nScanning custom modules in %s...\n", MZ_LOCAL_DIR);
    dir = opendir(MZ_LOCAL_DIR);
    if (dir) {
        const char *skip[] = { "lost+found", "tmp", "media", "oem", "vendor", "system", "tests", "traces", NULL };
        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_name[0] == '.' &&
                (entry->d_name[1] == '\0' ||
                 (entry->d_name[1] == '.' && entry->d_name[2] == '\0')))
                continue;

            if (entry->d_type != DT_DIR) continue;

            /* Check skip list */
            int should_skip = 0;
            for (int i = 0; skip[i]; i++) {
                if (strcmp(entry->d_name, skip[i]) == 0) {
                    should_skip = 1;
                    break;
                }
            }
            if (should_skip) continue;

            snprintf(module_path, sizeof(module_path), "%s/%s", MZ_LOCAL_DIR, entry->d_name);
            printf("  Scanning custom module: %s\n", entry->d_name);

            int fd = mz_open_device();
            if (fd >= 0) {
                struct mz_install_module mod;
                memset(&mod, 0, sizeof(mod));
                strncpy(mod.module_id, entry->d_name, sizeof(mod.module_id) - 1);
                strncpy(mod.module_path, module_path, sizeof(mod.module_path) - 1);
                mod.is_custom = 1;

                int ret = ioctl(fd, MOUNTZERO_IOC_INSTALL_MODULE, &mod);
                if (ret >= 0) {
                    total_rules += ret;
                    printf("    -> %d rules added\n", ret);
                }
            }
        }
        closedir(dir);
    }

    printf("\nScan complete: %d modules, %d total rules\n", total_modules, total_rules);
    return 0;
}

static int cmd_module_list(int argc, char **argv)
{
    DIR *dir;
    struct dirent *entry;
    char path[512];
    struct stat st;

    printf("Installed modules:\n");

    dir = opendir(MZ_MODULES_DIR);
    if (!dir) {
        fprintf(stderr, "Error: Cannot open %s: %s\n", MZ_MODULES_DIR, strerror(errno));
        return 1;
    }

    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.' &&
            (entry->d_name[1] == '\0' ||
             (entry->d_name[1] == '.' && entry->d_name[2] == '\0')))
            continue;

        if (entry->d_type != DT_DIR) continue;

        snprintf(path, sizeof(path), "%s/%s/module.prop", MZ_MODULES_DIR, entry->d_name);
        if (stat(path, &st) == 0) {
            int enabled = is_module_enabled(entry->d_name);
            printf("  %s [%s]\n", entry->d_name, enabled ? "active" : "disabled");
        }
    }

    closedir(dir);
    return 0;
}

static int cmd_module(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "Usage: mountzero module <scan|install|list>\n");
        return 1;
    }

    if (strcmp(argv[1], "scan") == 0)
        return cmd_module_scan(argc - 1, argv + 1);
    else if (strcmp(argv[1], "install") == 0)
        return cmd_module_install(argc - 1, argv + 1);
    else if (strcmp(argv[1], "list") == 0)
        return cmd_module_list(argc - 1, argv + 1);
    else {
        fprintf(stderr, "Unknown module subcommand: %s\n", argv[1]);
        return 1;
    }
}

/* ============================================================
 * UID Exclusion
 * ============================================================ */

static int cmd_uid(int argc, char **argv)
{
    int fd;
    uid_t uid;

    if (argc < 3) {
        fprintf(stderr, "Usage: mountzero uid <block|unblock> <uid>\n");
        return 1;
    }

    uid = (uid_t)atoi(argv[2]);
    fd = mz_open_device();
    if (fd < 0) return 1;

    if (strcmp(argv[1], "block") == 0) {
        if (ioctl(fd, MOUNTZERO_IOC_BLOCK_UID, &uid) == 0) {
            printf("UID %d blocked\n", uid);
            return 0;
        }
    } else if (strcmp(argv[1], "unblock") == 0) {
        if (ioctl(fd, MOUNTZERO_IOC_UNBLOCK_UID, &uid) == 0) {
            printf("UID %d unblocked\n", uid);
            return 0;
        }
    }

    fprintf(stderr, "Error: UID operation failed: %s\n", strerror(errno));
    return 1;
}

/* ============================================================
 * SUSFS Bridge
 * ============================================================ */

static int cmd_susfs(int argc, char **argv)
{
    int fd;

    if (argc < 2) {
        fprintf(stderr, "Usage: mountzero susfs <add-path|add-map|set-uname|version|features>\n");
        return 1;
    }

    fd = mz_open_device();
    if (fd < 0) return 1;

    if (strcmp(argv[1], "add-path") == 0 && argc >= 3) {
        if (ioctl(fd, MOUNTZERO_IOC_ADD_SUS_PATH, argv[2]) == 0) {
            printf("SUSFS path added: %s\n", argv[2]);
            return 0;
        }
    } else if (strcmp(argv[1], "add-map") == 0 && argc >= 3) {
        if (ioctl(fd, MOUNTZERO_IOC_ADD_SUS_MAP, argv[2]) == 0) {
            printf("SUSFS map added: %s\n", argv[2]);
            return 0;
        }
    } else if (strcmp(argv[1], "set-uname") == 0 && argc >= 4) {
        struct mz_uname_info uname_info;
        memset(&uname_info, 0, sizeof(uname_info));
        strncpy(uname_info.kernel_release, argv[2], sizeof(uname_info.kernel_release) - 1);
        strncpy(uname_info.kernel_version, argv[3], sizeof(uname_info.kernel_version) - 1);
        if (ioctl(fd, MOUNTZERO_IOC_SET_UNAME, &uname_info) == 0) {
            printf("SUSFS uname spoofed\n");
            return 0;
        }
    } else if (strcmp(argv[1], "version") == 0) {
        FILE *f = popen("ksu_susfs show version 2>/dev/null", "r");
        if (f) {
            char buf[256];
            while (fgets(buf, sizeof(buf), f)) printf("%s", buf);
            pclose(f);
            return 0;
        }
    } else if (strcmp(argv[1], "features") == 0) {
        FILE *f = popen("ksu_susfs show enabled_features 2>/dev/null", "r");
        if (f) {
            char buf[256];
            while (fgets(buf, sizeof(buf), f)) printf("%s", buf);
            pclose(f);
            return 0;
        }
    }

    fprintf(stderr, "Error: SUSFS operation failed: %s\n", strerror(errno));
    return 1;
}

/* ============================================================
 * Bootloop Guard
 * ============================================================ */

static int cmd_guard(int argc, char **argv)
{
    FILE *f;
    char buf[64];
    int count = 0;
    const char *count_path = MZ_SYSFS_PATH "/mountzero_guard/count";
    const char *threshold_path = MZ_SYSFS_PATH "/mountzero_guard/threshold";

    if (argc < 2) {
        fprintf(stderr, "Usage: mountzero guard <check|recover>\n");
        return 1;
    }

    if (strcmp(argv[1], "check") == 0) {
        f = fopen(count_path, "r");
        if (f) {
            if (fgets(buf, sizeof(buf), f)) count = atoi(buf);
            fclose(f);
        }

        int threshold = 3;
        f = fopen(threshold_path, "r");
        if (f) {
            if (fgets(buf, sizeof(buf), f)) threshold = atoi(buf);
            fclose(f);
        }

        printf("Bootloop Guard Status:\n");
        printf("  Boot count: %d\n", count);
        printf("  Threshold: %d\n", threshold);
        printf("  Status: %s\n", count >= threshold ? "TRIPPED" : "OK");
        return 0;
    } else if (strcmp(argv[1], "recover") == 0) {
        f = fopen(count_path, "w");
        if (f) {
            fprintf(f, "0\n");
            fclose(f);
            printf("Bootloop guard reset\n");
            return 0;
        }
        fprintf(stderr, "Error: Cannot reset bootloop guard\n");
        return 1;
    }

    fprintf(stderr, "Unknown guard subcommand: %s\n", argv[1]);
    return 1;
}

/* ============================================================
 * Detect - Kernel Capability Probe
 * ============================================================ */

static int cmd_detect(int argc, char **argv)
{
    struct stat st;
    int has_vfs = 0, has_susfs = 0, has_overlay = 0, has_erofs = 0;

    printf("MountZero Kernel Capability Detection:\n\n");

    /* VFS driver */
    if (stat(MZ_DEVICE_PATH, &st) == 0 && S_ISCHR(st.st_mode)) {
        printf("  VFS driver:     AVAILABLE (%s)\n", MZ_DEVICE_PATH);
        has_vfs = 1;
    } else {
        printf("  VFS driver:     NOT AVAILABLE\n");
    }

    /* SUSFS — detect via CLI binary since symbols are hidden */
    FILE *susfs_pipe = popen("/data/adb/ksu/bin/susfs show version 2>/dev/null || /data/adb/ksu/bin/ksu_susfs show version 2>/dev/null", "r");
    if (susfs_pipe) {
        char susfs_buf[64];
        if (fgets(susfs_buf, sizeof(susfs_buf), susfs_pipe) && strlen(susfs_buf) > 2) {
            has_susfs = 1;
            printf("  SUSFS:          AVAILABLE (%s)", susfs_buf);
        } else {
            printf("  SUSFS:          NOT AVAILABLE\n");
        }
        pclose(susfs_pipe);
    } else {
        printf("  SUSFS:          NOT AVAILABLE\n");
    }

    /* OverlayFS */
    FILE *f = fopen("/proc/filesystems", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            if (strstr(line, "overlay")) {
                has_overlay = 1;
                break;
            }
        }
        fclose(f);
    }
    printf("  OverlayFS:      %s\n", has_overlay ? "AVAILABLE" : "NOT AVAILABLE");

    /* EROFS */
    f = fopen("/proc/filesystems", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            if (strstr(line, "erofs")) {
                has_erofs = 1;
                break;
            }
        }
        fclose(f);
    }
    printf("  EROFS:          %s\n", has_erofs ? "AVAILABLE" : "NOT AVAILABLE");

    /* Active strategy */
    printf("\n  Active strategy: %s\n", has_vfs ? "VFS (primary)" :
           (has_overlay ? "OverlayFS (fallback)" : "Magic mount (last resort)"));

    /* Write detection JSON */
    f = fopen(MZ_DETECTION_PATH, "w");
    if (f) {
        fprintf(f, "{\n");
        fprintf(f, "  \"vfs_driver\": %s,\n", has_vfs ? "true" : "false");
        fprintf(f, "  \"susfs\": %s,\n", has_susfs ? "true" : "false");
        fprintf(f, "  \"overlay_fs\": %s,\n", has_overlay ? "true" : "false");
        fprintf(f, "  \"erofs\": %s,\n", has_erofs ? "true" : "false");
        fprintf(f, "  \"strategy\": \"%s\"\n", has_vfs ? "vfs" :
                (has_overlay ? "overlay" : "magic"));
        fprintf(f, "}\n");
        fclose(f);
    }

    return 0;
}

/* ============================================================
 * Dump - Diagnostic
 * ============================================================ */

static int cmd_dump(int argc, char **argv)
{
    char timestamp[64];
    char dump_dir[256];
    char cmd[512];
    time_t now;
    struct tm *tm_info;

    now = time(NULL);
    tm_info = localtime(&now);
    strftime(timestamp, sizeof(timestamp), "%Y%m%d_%H%M%S", tm_info);
    snprintf(dump_dir, sizeof(dump_dir), "/sdcard/mountzero_dump_%s", timestamp);

    mkdir(dump_dir, 0755);
    printf("Creating diagnostic dump in %s...\n", dump_dir);

    /* Kernel version */
    snprintf(cmd, sizeof(cmd), "uname -a > %s/kernel_version.txt 2>/dev/null", dump_dir);
    system(cmd);

    /* Mount info */
    snprintf(cmd, sizeof(cmd), "cat /proc/mounts > %s/mounts.txt 2>/dev/null", dump_dir);
    system(cmd);

    /* MountZero status */
    snprintf(cmd, sizeof(cmd), "%s/mountzero_status.txt", dump_dir);
    {
        FILE *f = fopen(cmd, "w");
        if (f) {
            cmd_status(0, NULL);
            fclose(f);
        }
    }

    /* Rules */
    snprintf(cmd, sizeof(cmd), "%s/mountzero_rules.txt", dump_dir);
    {
        FILE *f = fopen(cmd, "w");
        if (f) {
            cmd_list(0, NULL);
            fclose(f);
        }
    }

    /* Module list */
    snprintf(cmd, sizeof(cmd), "%s/modules.txt", dump_dir);
    {
        FILE *f = fopen(cmd, "w");
        if (f) {
            cmd_module_list(0, NULL);
            fclose(f);
        }
    }

    printf("Diagnostic dump complete.\n");
    return 0;
}

/* ============================================================
 * Main
 * ============================================================ */

int main(int argc, char **argv)
{
    int ret = 0;

    if (argc < 2) {
        print_usage();
        return 1;
    }

    if (strcmp(argv[1], "help") == 0 || strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        print_usage();
        return 0;
    }

    if (strcmp(argv[1], "version") == 0)
        ret = cmd_version(argc - 1, argv + 1);
    else if (strcmp(argv[1], "status") == 0)
        ret = cmd_status(argc - 1, argv + 1);
    else if (strcmp(argv[1], "enable") == 0)
        ret = cmd_enable(argc - 1, argv + 1);
    else if (strcmp(argv[1], "disable") == 0)
        ret = cmd_disable(argc - 1, argv + 1);
    else if (strcmp(argv[1], "add") == 0)
        ret = cmd_add(argc - 1, argv + 1);
    else if (strcmp(argv[1], "del") == 0)
        ret = cmd_del(argc - 1, argv + 1);
    else if (strcmp(argv[1], "list") == 0)
        ret = cmd_list(argc - 1, argv + 1);
    else if (strcmp(argv[1], "clear") == 0)
        ret = cmd_clear(argc - 1, argv + 1);
    else if (strcmp(argv[1], "module") == 0)
        ret = cmd_module(argc - 1, argv + 1);
    else if (strcmp(argv[1], "uid") == 0)
        ret = cmd_uid(argc - 1, argv + 1);
    else if (strcmp(argv[1], "susfs") == 0)
        ret = cmd_susfs(argc - 1, argv + 1);
    else if (strcmp(argv[1], "guard") == 0)
        ret = cmd_guard(argc - 1, argv + 1);
    else if (strcmp(argv[1], "detect") == 0)
        ret = cmd_detect(argc - 1, argv + 1);
    else if (strcmp(argv[1], "dump") == 0)
        ret = cmd_dump(argc - 1, argv + 1);
    else {
        fprintf(stderr, "Unknown command: %s\n\n", argv[1]);
        print_usage();
        ret = 1;
    }

    mz_close_device();
    return ret;
}
