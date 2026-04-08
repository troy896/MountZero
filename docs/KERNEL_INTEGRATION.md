# Kernel Integration Guide

## Prerequisites

Your kernel must already have:
- **KernelSU** integrated
- **SUSFS** patches applied (`CONFIG_KSU_SUSFS=y`)

MountZero only adds the VFS path redirection layer on top of your existing SUSFS setup.

## Quick Integration

```bash
cd MountZero_Project
./scripts/patch_kernel.sh /path/to/kernel/source
```

That's it. The script will:
1. Copy MountZero source files to your kernel tree
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
      Works alongside SUSFS to provide:
      - Automatic module mounting at boot
      - Path redirection without overlayfs
      - Virtual directory injection
      - Fast bloom filter lookups
      - Hot-plug module detection
      - SUSFS bridge integration
```

### 4. Hook into fs/namei.c

**Add include** near the top (after other kernel includes):

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
```

Ensure SUSFS is already enabled:
```
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

## Troubleshooting

### Build Error: "undefined reference to mountzero_*"
- Ensure both `mountzero.c` and `mountzero_vfs.c` are compiled
- Check `fs/Makefile` has `obj-$(CONFIG_MOUNTZERO) += mountzero.o mountzero_vfs.o`

### Build Error: "mountzero_vfs.h not found"
- Verify headers are in `include/linux/`
- Check `#include <linux/mountzero_vfs.h>` in `fs/namei.c`

### Bootloop after flashing
- MountZero has built-in bootloop guard (3 failures → skip mount)
- Hold Volume Up + Down during boot to trigger safe mode
- Flash kernel without MountZero config

### Modules not mounting
- Check `dmesg | grep mountzero` for errors
- Verify `/dev/mountzero` exists
- Ensure `CONFIG_KSU_SUSFS=y` is enabled

### WebUI not showing
- Check module files: `ls /data/adb/modules/mountzero_vfs/webroot/`
- Verify `metamodule=1` in `module.prop`
- Check KSU version supports WebUI

## Kernel Version Compatibility

| Kernel Version | Status | Notes |
|---------------|--------|-------|
| 4.14.x | ✅ Tested | Samsung MT6768 (this kernel) |
| 5.4.x | ✅ Compatible | GKI kernels |
| 5.10.x | ✅ Compatible | Android 12/13 GKI |
| 5.15.x | ✅ Compatible | Android 13/14 GKI |
| 6.1.x | ⚠️ May need adjustment | namei.c structure changed |
| 6.6.x | ⚠️ May need adjustment | namei.c structure changed |
