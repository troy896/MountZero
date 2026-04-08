# MountZero VFS — Complete Kernel Integration

<p align="center">
  <strong>🔥 VFS-level path redirection + SUSFS root evasion for KernelSU/APatch</strong>
</p>

<p align="center">
  <a href="https://github.com/mafiadan6/MountZero/releases"><img src="https://img.shields.io/badge/Download%20Module-v2.0.0-blue?style=for-the-badge&logo=github" alt="Download Module"></a>
  <a href="https://t.me/mastermindszs"><img src="https://img.shields.io/badge/Telegram-@mastermindszs-2CA5E0?style=for-the-badge&logo=telegram" alt="Telegram"></a>
</p>

## Overview

MountZero VFS is a **built-in kernel module** that provides VFS-level path redirection for KernelSU/APatch modules. It works alongside SUSFS (already in your kernel) to provide:

- **VFS Path Redirection** — transparent file redirection at the VFS layer, no overlay mounts needed
- **Auto Module Scanning** — recursively scans `/data/adb/modules/` and `/data/local/` at boot
- **SUSFS Bridge** — full integration with all 9 SUSFS features
- **BRENE Hiding Engine** — root evasion: path hiding, maps hiding, prop spoofing, cmdline spoofing
- **Hot-Plug Detection** — watches for new modules without reboot
- **Bootloop Guard** — automatically skips mount pipeline after 3 failed boots
- **WebUI Management** — 6-tab KernelSU WebUI for full control

## 📦 Module Download

> **⚠️ Required:** You MUST install the MountZero Manager module for the VFS driver to work properly.  
> The kernel patch only adds the driver — the module provides the management layer, WebUI, and mounting scripts.

<div align="center">
  <h3>
    <a href="https://github.com/mafiadan6/MountZero/releases">
      📥 Download MountZero Manager v2.0.0
    </a>
  </h3>
  <p><em>Flash via KernelSU → Modules → Install from storage</em></p>
</div>

## 📢 Community

Join the Telegram channel for updates, support, and discussion:

<div align="center">
  <h3>
    <a href="https://t.me/mastermindszs">
      💬 @mastermindszs on Telegram
    </a>
  </h3>
</div>

## Prerequisites

**Your kernel must already have:**
- KernelSU integrated
- SUSFS patches applied (`CONFIG_KSU_SUSFS=y`)

MountZero only adds the VFS path redirection layer on top of SUSFS.

## Quick Start

```bash
# 1. Apply MountZero patches only
cd MountZero_Project
./scripts/patch_kernel.sh /path/to/kernel/source

# 2. Ensure CONFIG_MOUNTZERO=y in defconfig
# 3. Build kernel
make -j$(nproc)

# 4. Flash kernel and MountZero_Manager module
#    📥 Download: https://github.com/mafiadan6/MountZero/releases
# 5. Reboot
```

> **⚠️ Required:** The MountZero Manager module MUST be installed via KernelSU for the VFS driver to work. The kernel patch adds the driver, but the module provides the WebUI, mounting scripts, and management layer. Without the module, the VFS driver has no way to manage rules or scan modules.

## 📢 Stay Updated

Join the Telegram channel for releases, support, and discussion:

**[💬 @mastermindszs on Telegram](https://t.me/mastermindszs)**

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              KernelSU Manager (WebUI)                   │
│  6 Tabs: Status, Modules, Rules, Config, Guard, Tools   │
│  Communicates via: ksu.exec() → mzctl → IOCTL → kernel  │
└──────────────────────┬──────────────────────────────────┘
                       │ shell commands
                       ▼
┌─────────────────────────────────────────────────────────┐
│              mzctl CLI (/data/adb/ksu/bin/mzctl)        │
│  version, status, enable/disable, add/del/list/clear,   │
│  module scan/install/list, uid block/unblock,           │
│  susfs, guard, detect, dump                             │
└──────────────────────┬──────────────────────────────────┘
                       │ IOCTL on /dev/mountzero
                       ▼
┌─────────────────────────────────────────────────────────┐
│              Kernel (fs/mountzero.c)                    │
│  ├─ VFS path redirection (hash table + bloom filter)    │
│  ├─ Auto module scanner (late_initcall_sync)            │
│  ├─ Hot-plug kernel thread (5s polling)                 │
│  ├─ SUSFS bridge (all 9 features)                       │
│  ├─ Bootloop guard (skip after 3 failures)              │
│  └─ Sysfs: /sys/kernel/mountzero/                       │
└──────────────────────┬──────────────────────────────────┘
                       │ VFS hooks in fs/namei.c
                       ▼
┌─────────────────────────────────────────────────────────┐
│              VFS Layer (fs/namei.c)                     │
│  mountzero_vfs_getname_hook() intercepts path lookups   │
└─────────────────────────────────────────────────────────┘
```

## Kernel Changes

### New Files Added
| File | Lines | Purpose |
|------|-------|---------|
| `fs/mountzero.c` | ~1350 | Core: rule management, scanner, SUSFS bridge, hot-plug, sysfs |
| `fs/mountzero_vfs.c` | ~300 | VFS hooks: path redirection, directory injection, statfs/xattr spoofing |
| `fs/mountzero_cli.c` | ~950 | Userspace CLI tool source (compiled to `mzctl` binary) |
| `include/linux/mountzero.h` | ~140 | Public header: IOCTL interface, function declarations |
| `include/linux/mountzero_def.h` | ~50 | Internal definitions: rule struct, flags, hash table |
| `include/linux/mountzero_vfs.h` | ~70 | VFS hook header with CONFIG guards |

### Existing Files Modified
| File | Changes |
|------|---------|
| `fs/Makefile` | `obj-$(CONFIG_MOUNTZERO) += mountzero.o mountzero_vfs.o` |
| `fs/Kconfig` | `config MOUNTZERO` entry (depends on KSU_SUSFS) |
| `fs/namei.c` | Include `mountzero_vfs.h`, call `mountzero_vfs_getname_hook()` |

## Configuration

```
CONFIG_MOUNTZERO=y
CONFIG_MOUNTZERO depends on KSU_SUSFS
```

## Features

### VFS Path Redirection
- Hash table + bloom filter for fast lookups
- Automatic module scanning at boot
- Hot-plug detection for new modules
- Works without overlay mounts (no /proc/mounts entries)

### SUSFS Integration (All 9 Features)
- Path hiding (`CONFIG_KSU_SUSFS_SUS_PATH`)
- Mount hiding (`CONFIG_KSU_SUSFS_SUS_MOUNT`)
- Kstat spoofing (`CONFIG_KSU_SUSFS_SUS_KSTAT`)
- Uname spoofing (`CONFIG_KSU_SUSFS_SPOOF_UNAME`)
- Kernel logging (`CONFIG_KSU_SUSFS_ENABLE_LOG`)
- Symbol hiding (`CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS`)
- Cmdline spoofing (`CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG`)
- Open redirect (`CONFIG_KSU_SUSFS_OPEN_REDIRECT`)
- Maps hiding (`CONFIG_KSU_SUSFS_SUS_MAP`)

### BRENE Hiding Engine
- Path hiding (KSU, Magisk, root detection paths)
- Maps hiding (Zygisk, LSPosed injection libraries)
- Android system properties spoofing (20+ props)
- Cmdline/bootconfig spoofing
- Mount hiding from non-su processes
- AVC log spoofing
- LSPosed hiding (dex2oat paths)
- ext4 loop/jbd2 hiding

## License

GPL v2.0

## Author

爪卂丂ㄒ乇尺爪工刀ᗪ丂 (Mastermind)

## Version

v2.0.0
