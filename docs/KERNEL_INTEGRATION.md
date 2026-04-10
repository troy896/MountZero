# Kernel Integration Guide

## Target Kernel

This project is **built and tested for Android 4.14 kernels** (Samsung MT6768 platform).

It can also be integrated into **5.x/6.x GKI kernels** that already have SUSFS 2.1.0 and KernelSU/APatch integrated. The source files and patching process are identical across kernel versions — the only potential adjustment is the `fs/namei.c` hook location, which the patch script handles automatically.

> **Important:** This repository does NOT include SUSFS patches. Your kernel must already have SUSFS v2.1.0 (`CONFIG_KSU_SUSFS=y`) and KernelSU/APatch integrated before applying MountZero.

## Step 0: Apply SUSFS Patches (If Not Already Integrated)

If your kernel doesn't have SUSFS, apply the SUSFS v2.1.0 patches **before** applying MountZero. Use the correct patch for your kernel version:

| Your Kernel Version | SUSFS Patch to Apply |
|---------------------|---------------------|
| **4.14.x** | [Super-Builders: `50_add_susfs_in_gki-android-4.14.patch`](https://github.com/Enginex0/Super-Builders/blob/main/android14-5.15/ReSukiSU/patches/50_add_susfs_in_gki-android-4.14.patch) |
| **5.4.x** | [Super-Builders: `50_add_susfs_in_gki-android12-5.4.patch`](https://github.com/Enginex0/Super-Builders/blob/main/android12-5.4/ReSukiSU/patches/50_add_susfs_in_gki-android12-5.4.patch) |
| **5.10.x** | [Super-Builders: `50_add_susfs_in_gki-android12-5.10.patch`](https://github.com/Enginex0/Super-Builders/blob/main/android12-5.10/ReSukiSU/patches/50_add_susfs_in_gki-android12-5.10.patch) |
| **5.15.x** | [Super-Builders: `50_add_susfs_in_gki-android13-5.15.patch`](https://github.com/Enginex0/Super-Builders/blob/main/android13-5.15/ReSukiSU/patches/50_add_susfs_in_gki-android13-5.15.patch) |
| **6.1.x** | [Super-Builders: `50_add_susfs_in_gki-android14-6.1.patch`](https://github.com/Enginex0/Super-Builders/blob/main/android14-6.1/ReSukiSU/patches/50_add_susfs_in_gki-android14-6.1.patch) |
| **6.6.x** | [Super-Builders: `50_add_susfs_in_gki-android14-6.6.patch`](https://github.com/Enginex0/Super-Builders/blob/main/android14-6.6/ReSukiSU/patches/50_add_susfs_in_gki-android14-6.6.patch) |

**To apply SUSFS patches:**
```bash
cd /path/to/kernel/source
patch -p1 < /path/to/50_add_susfs_in_gki-<your-kernel-version>.patch
```

**Also required:** KernelSU or APatch must be integrated first. See [KernelSU docs](https://kernelsu.org) or [APatch docs](https://apatch.org).

## Prerequisites

Your kernel must already have:
- **KernelSU** or **APatch** integrated
- **SUSFS v2.1.0** patches applied (`CONFIG_KSU_SUSFS=y`)

MountZero only adds the VFS path redirection layer on top of SUSFS. It does NOT include SUSFS patches.

## Quick Integration

```bash
cd MountZero_Project
./scripts/patch_kernel.sh /path/to/kernel/source
```

This script will:
1. Copy `mountzero.c`, `mountzero_vfs.c`, and headers to your kernel tree
2. Update `fs/Makefile` to build mountzero
3. Update `fs/Kconfig` to add `CONFIG_MOUNTZERO`
4. Hook MountZero into `fs/namei.c` for VFS path interception

## Manual Integration

If the script doesn't work for your kernel, follow these steps manually:

### 1. Copy Source Files

```bash
KERNEL=/path/to/your/kernel/source
MZ=MountZero_Project/kernel/source_files

cp $MZ/fs/mountzero.c $KERNEL/fs/mountzero.c
cp $MZ/fs/mountzero_vfs.c $KERNEL/fs/mountzero_vfs.c
cp $MZ/include/linux/mountzero.h $KERNEL/include/linux/mountzero.h
cp $MZ/include/linux/mountzero_def.h $KERNEL/include/linux/mountzero_def.h
cp $MZ/include/linux/mountzero_vfs.h $KERNEL/include/linux/mountzero_vfs.h
```

### 2. Update fs/Makefile

Add this line to `fs/Makefile`:

```makefile
obj-$(CONFIG_MOUNTZERO)		+= mountzero.o mountzero_vfs.o
```

### 3. Update fs/Kconfig

Add this to `fs/Kconfig`:

```kconfig
config MOUNTZERO
    bool "MountZero VFS Path Redirection System"
    depends on KSU_SUSFS
    default y
    help
      VFS-level path redirection for KernelSU modules.
      Works alongside SUSFS v2.1.0 to provide:
      - Automatic module mounting at boot
      - Path redirection without overlayfs
      - Virtual directory injection
      - Fast bloom filter lookups
      - Hot-plug module detection
      - SUSFS bridge integration
      - BRENE root evasion engine
      - Direct uname spoofing
      - Bootloop guard
```

### 4. Hook MountZero into fs/namei.c

**Add include** near the top (after SUSFS includes):

```c
#ifdef CONFIG_MOUNTZERO
#include <linux/mountzero_vfs.h>
#endif
```

**Add hook** in `getname_flags()` function (the main path resolution function):

```c
#ifdef CONFIG_MOUNTZERO
    /* MountZero VFS path redirection */
    result = mountzero_vfs_getname_hook(result);
#endif
```

Place this just before the function returns `struct filename *result`.

### 5. Configure Kernel

```bash
make ARCH=arm64 menuconfig
```

Enable:
```
File systems  --->
    [*] MountZero VFS Path Redirection System (CONFIG_MOUNTZERO=y)

KernelSU  --->
    [*] SUSFS support (CONFIG_KSU_SUSFS=y)
    [*]   SUSFS path hiding (CONFIG_KSU_SUSFS_SUS_PATH)
    [*]   SUSFS mount hiding (CONFIG_KSU_SUSFS_SUS_MOUNT)
    [*]   SUSFS kstat spoofing (CONFIG_KSU_SUSFS_SUS_KSTAT)
    [*]   SUSFS uname spoofing (CONFIG_KSU_SUSFS_SPOOF_UNAME)
    [*]   SUSFS kernel logging (CONFIG_KSU_SUSFS_ENABLE_LOG)
    [*]   SUSFS symbol hiding (CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS)
    [*]   SUSFS cmdline spoofing (CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG)
    [*]   SUSFS open redirect (CONFIG_KSU_SUSFS_OPEN_REDIRECT)
    [*]   SUSFS maps hiding (CONFIG_KSU_SUSFS_SUS_MAP)
```

### 6. Build

```bash
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```

### 7. Flash

Flash the kernel image and the MountZero_Manager module:
```bash
# Flash kernel (method depends on device)
fastboot flash boot boot.img

# Flash module via KernelSU
adb push MountZero_Project/module/MountZero-Manager-v2.0.0-FLASHABLE.zip /sdcard/
# Then install via KSU app
```

---

## What MountZero Adds to Your Kernel

### New Files
| File | Lines | Purpose |
|------|-------|---------|
| `fs/mountzero.c` | ~1400 | Core VFS driver, SUSFS bridge, uname spoof, bootloop guard, sysfs |
| `fs/mountzero_vfs.c` | ~300 | VFS hooks: path redirection, directory injection, statfs/xattr spoofing |
| `fs/mountzero_cli.c` | ~1000 | Userspace CLI tool source (compiled to `mzctl` binary) |
| `include/linux/mountzero.h` | ~160 | Public header: IOCTL interface, function declarations |
| `include/linux/mountzero_def.h` | ~50 | Internal definitions: rule struct, flags, hash table |
| `include/linux/mountzero_vfs.h` | ~70 | VFS hook header with CONFIG guards |

### Modified Files
| File | Changes |
|------|---------|
| `fs/Makefile` | `obj-$(CONFIG_MOUNTZERO) += mountzero.o mountzero_vfs.o` |
| `fs/Kconfig` | `config MOUNTZERO` entry (depends on KSU_SUSFS) |
| `fs/namei.c` | Include `mountzero_vfs.h`, call `mountzero_vfs_getname_hook()` |

### Key Features
- **VFS Path Redirection**: Hash table (1024 buckets) + 8192-bit bloom filter
- **Auto Module Scanner**: Scans `/data/adb/modules/` and `/data/local/` at boot via `late_initcall_sync`
- **Hot-Plug Thread**: Kernel thread polling every 5 seconds
- **SUSFS Bridge**: Direct supercall interface to all 9 SUSFS features
- **Direct Uname Spoofing**: Bypasses SUSFS binary bug for custom values
- **Bootloop Guard**: Stored in `/data/adb/mountzero/.bootcount`, skips mount after 3 failures
- **Sysfs Interface**: `/sys/kernel/mountzero/` for version, status, guard config

---

## Kernel Version Compatibility

| Kernel Version | Status | Notes |
|---------------|--------|-------|
| 4.14.x | ✅ Tested | Samsung MT6768 (this kernel) |
| 5.4.x | ✅ Compatible | GKI kernels with SUSFS 2.1.0 |
| 5.10.x | ✅ Compatible | Android 12/13 GKI with SUSFS 2.1.0 |
| 5.15.x | ✅ Compatible | Android 13/14 GKI with SUSFS 2.1.0 |
| 6.1.x | ⚠️ May need adjustment | namei.c structure changed |
| 6.6.x | ⚠️ May need adjustment | namei.c structure changed |

### Integration Notes for 5.x+ Kernels

MountZero was developed for 4.14 kernels, but the source files work on 5.x/6.x GKI kernels with minimal changes:

1. **fs/namei.c hook location** — The `getname_flags()` function structure may differ slightly. The `patch_kernel.sh` script auto-detects the correct location, but you may need to manually place the hook if auto-detection fails.

2. **SUSFS supercall compatibility** — MountZero uses the same `syscall(SYS_reboot, ...)` supercall mechanism as SUSFS 2.1.0. If your kernel uses a different SUSFS version, the supercall commands may not work.

3. **`compat_ptr_ioctl`** — If your kernel doesn't have `compat_ptr_ioctl`, the mountzero file operations will fall back to using `mountzero_ioctl` directly for compat ioctls (already handled in the source).

4. **Build system** — The `obj-$(CONFIG_MOUNTZERO) += mountzero.o mountzero_vfs.o` line in `fs/Makefile` works identically across all kernel versions.
