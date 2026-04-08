# MountZero VFS

<p align="center">
  <strong>🔥 VFS-level path redirection + SUSFS root evasion for KernelSU/APatch</strong>
</p>

<p align="center">
  <a href="https://github.com/mafiadan6/MountZero/releases"><img src="https://img.shields.io/badge/Download-v2.0.0-blue?style=for-the-badge&logo=github" alt="Download"></a>
  <a href="https://t.me/mastermindszs"><img src="https://img.shields.io/badge/Telegram-@mastermindszs-2CA5E0?style=for-the-badge&logo=telegram" alt="Telegram"></a>
  <a href="https://github.com/mafiadan6/MountZero/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-GPL--2.0-green?style=for-the-badge" alt="License"></a>
</p>

---

## 📖 Overview

MountZero VFS is a **built-in kernel module** that provides VFS-level path redirection for KernelSU/APatch modules. It works alongside **SUSFS v2.1.0** to deliver complete root hiding and module management without traditional overlay mounts.

### What Makes MountZero Different

Traditional root solutions use overlayfs to mount module files over the system partition. MountZero intercepts file lookups at the VFS layer and redirects them transparently — **zero mounts, zero /proc/mounts entries, zero detection surface**.

## ✨ Features

### 🔮 Enchanted SUSFS VFS Engine
- **VFS Path Redirection** — transparent file redirection at the VFS layer, no overlay mounts needed
- **Auto Module Scanning** — recursively scans `/data/adb/modules/` and `/data/local/` at boot
- **Hot-Plug Detection** — watches for new modules without reboot (5s polling)
- **Bloom Filter Lookups** — O(1) rule resolution with 8192-bit bloom filter
- **Bootloop Guard** — automatically skips mount pipeline after 3 failed boots

### 🛡️ SUSFS Integration (All 9 Features)
| Feature | Config | Description |
|---------|--------|-------------|
| Path Hiding | `CONFIG_KSU_SUSFS_SUS_PATH` | Hide files/dirs from `readdir` and path lookups |
| Mount Hiding | `CONFIG_KSU_SUSFS_SUS_MOUNT` | Hide mounts from non-su processes |
| Kstat Spoofing | `CONFIG_KSU_SUSFS_SUS_KSTAT` | Spoof file metadata (inode, dev, size, timestamps) |
| Uname Spoofing | `CONFIG_KSU_SUSFS_SPOOF_UNAME` | Spoof `uname -r` / `uname -v` output |
| Kernel Logging | `CONFIG_KSU_SUSFS_ENABLE_LOG` | Enable/disable SUSFS kernel logging |
| Symbol Hiding | `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | Hide kernel symbols from `/proc/kallsyms` |
| Cmdline Spoofing | `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` | Spoof `/proc/cmdline` or bootconfig |
| Open Redirect | `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | Redirect file opens based on UID scheme |
| Maps Hiding | `CONFIG_KSU_SUSFS_SUS_MAP` | Hide library mappings from `/proc/PID/maps` |

### 👻 BRENE Root Evasion Engine
- **Path Hiding** — KSU, Magisk, root detection paths hidden from detection
- **Maps Hiding** — Zygisk, LSPosed injection libraries hidden from `/proc/PID/maps`
- **Properties Spoofing** — 20+ Android system properties spoofed (`ro.secure`, `ro.debuggable`, `ro.boot.flash.locked`, etc.)
- **Cmdline/Bootconfig Spoofing** — Clean boot state shown to detectors
- **LSPosed Hiding** — dex2oat paths hidden from detection
- **ext4 Loop/JBD2 Hiding** — Module loop devices hidden from `/proc/fs/`
- **AVC Log Spoofing** — SELinux denial logs suppressed

### 🌐 WebUI Management
- **Status Tab** — System info, SUSFS version, VFS rule counts, capability detection
- **Modules Tab** — List all installed modules with active/disabled status, search/filter
- **VFS Rules Tab** — View, add, delete redirect rules
- **Config Tab** — Mount engine selection, SUSFS bridge, ADB root toggle
- **Guard Tab** — Bootloop guard status, threshold control, recovery
- **Tools Tab** — Kernel capability detection, diagnostic dump, module operations

## 📦 Module Download

> **⚠️ Required:** You MUST install the MountZero Manager module for the VFS driver to work. The kernel patch adds the driver — the module provides the WebUI, mounting scripts, and management layer.

<div align="center">
  <h3>
    <a href="https://github.com/mafiadan6/MountZero/releases">
      📥 Download MountZero Manager v2.0.0
    </a>
  </h3>
  <p><em>Flash via KernelSU → Modules → Install from storage</em></p>
</div>

## 🚀 Quick Start

### Prerequisites
- KernelSU or APatch already integrated
- Kernel 4.14 or 5.15 (arm64)
- SUSFS v2.1.0 patches (included if your kernel doesn't have them)

### Step 1: Apply SUSFS v2.1.0 Patches

```bash
cd MountZero_Project
./scripts/patch_susfs.sh /path/to/kernel/source
```

> **Note:** If your kernel already has SUSFS v2.1.0 applied, skip this step.

### Step 2: Apply MountZero VFS Patches

```bash
./scripts/patch_kernel.sh /path/to/kernel/source
```

This will:
1. Copy MountZero source files (`fs/mountzero.c`, `fs/mountzero_vfs.c`, headers)
2. Update `fs/Makefile` to build mountzero
3. Update `fs/Kconfig` to add `CONFIG_MOUNTZERO`
4. Hook MountZero into `fs/namei.c` for VFS path interception

### Step 3: Configure Kernel

Add to your defconfig:

```text
# SUSFS v2.1.0 (if not already set)
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y

# MountZero VFS
CONFIG_MOUNTZERO=y
```

### Step 4: Build & Flash

```bash
# Build kernel
make -j$(nproc)

# Flash kernel (method depends on device)
fastboot flash boot boot.img

# Flash MountZero Manager module via KernelSU
# 📥 Download: https://github.com/mafiadan6/MountZero/releases

# Reboot
```

## 🏗️ Architecture

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
│  ├─ SUSFS v2.1.0 bridge (all 9 features)                │
│  ├─ Bootloop guard (skip after 3 failures)              │
│  ├─ BRENE root evasion engine                           │
│  └─ Sysfs: /sys/kernel/mountzero/                       │
└──────────────────────┬──────────────────────────────────┘
                       │ VFS hooks in fs/namei.c
                       ▼
┌─────────────────────────────────────────────────────────┐
│              VFS Layer (fs/namei.c)                     │
│  mountzero_vfs_getname_hook() intercepts path lookups   │
└─────────────────────────────────────────────────────────┘
```

## 📂 Project Structure

```
MountZero_Project/
├── README.md                          # This file
├── LICENSE                            # GPL-2.0 license
├── GITHUB_RELEASE_NOTES.txt           # Release template for GitHub
├── kernel/
│   ├── patches/
│   │   ├── susfs-v2.1.0/              # SUSFS v2.1.0 kernel patches
│   │   │   ├── 001_susfs-v2.1.0-android-4.14.patch
│   │   │   └── 001_susfs-v2.1.0-android13-5.15.patch
│   │   └── mountzero/                 # MountZero VFS integration
│   │       ├── 001_mountzero_vfs_kernel_integration.patch
│   │       └── SOURCES.md
│   └── source_files/                  # Source files to copy to kernel tree
│       ├── fs/
│       │   ├── mountzero.c            # Core VFS driver (1350 lines)
│       │   ├── mountzero_vfs.c        # VFS hooks (300 lines)
│       │   └── mountzero_cli.c        # Userspace CLI source (950 lines)
│       └── include/linux/
│           ├── mountzero.h            # Public IOCTL interface
│           ├── mountzero_def.h        # Internal definitions
│           ├── mountzero_vfs.h        # VFS hook declarations
│           ├── susfs.h                # SUSFS v2.1.0 header
│           └── susfs_def.h            # SUSFS v2.1.0 definitions
├── module/
│   └── MountZero-Manager-v2.0.0-FLASHABLE.zip
├── scripts/
│   ├── patch_susfs.sh                 # SUSFS v2.1.0 patcher
│   ├── patch_kernel.sh                # MountZero VFS patcher
│   ├── susfs_inline_hook_patches.sh   # SUSFS namei.c/d_path.c hooks
│   └── apply_susfs_patch.py           # Python helper
└── docs/
    ├── KERNEL_INTEGRATION.md          # Detailed kernel patching guide
    └── MODULE_GUIDE.md                # Module usage guide
```

## ⚙️ Configuration

### MountZero VFS Config

| Config | Default | Description |
|--------|---------|-------------|
| `CONFIG_MOUNTZERO` | `y` | Enable MountZero VFS driver |
| Depends on | `KSU_SUSFS` | Requires SUSFS to be enabled |

### SUSFS v2.1.0 Config

| Config | Description |
|--------|-------------|
| `CONFIG_KSU_SUSFS` | SUSFS core |
| `CONFIG_KSU_SUSFS_SUS_PATH` | Path hiding |
| `CONFIG_KSU_SUSFS_SUS_MOUNT` | Mount hiding |
| `CONFIG_KSU_SUSFS_SUS_KSTAT` | Kstat spoofing |
| `CONFIG_KSU_SUSFS_SPOOF_UNAME` | Uname spoofing |
| `CONFIG_KSU_SUSFS_ENABLE_LOG` | Kernel logging |
| `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | Symbol hiding |
| `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` | Cmdline spoofing |
| `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | Open redirect |
| `CONFIG_KSU_SUSFS_SUS_MAP` | Maps hiding |

## 💻 CLI Usage

```bash
# Get into root shell
adb shell su

# Basic commands
mzctl version                    # Show MountZero version
mzctl status                     # Show VFS engine status
mzctl enable                     # Enable VFS engine
mzctl disable                    # Disable VFS engine

# Rule management
mzctl add /system/bin/su /data/adb/modules/X/system/bin/su   # Add rule
mzctl del /system/bin/su                                    # Delete rule
mzctl list                                                  # List all rules
mzctl clear                                                 # Clear all rules

# Module management
mzctl module scan                                           # Scan all modules
mzctl module install mymodule /data/adb/modules/mymodule    # Install module
mzctl module install Droidspaces /data/local/Droidspaces custom  # Custom module

# SUSFS operations
mzctl susfs add-path /data/adb/ksu       # Add hidden path
mzctl susfs add-map /data/adb/modules/X/zygisk.so  # Add hidden map
mzctl susfs set-uname "4.14.356" "#1 SMP PREEMPT"   # Spoof uname
mzctl susfs version                      # Show SUSFS version
mzctl susfs features                     # Show enabled SUSFS features

# Bootloop guard
mzctl guard check                        # Check guard status
mzctl guard recover                      # Reset guard after recovery

# Diagnostics
mzctl detect                             # Detect kernel capabilities
mzctl dump                               # Create diagnostic dump
```

## 🛡️ Troubleshooting

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
- Ensure MountZero Manager module is installed

### WebUI not showing
- Check module files: `ls /data/adb/modules/mountzero_vfs/webroot/`
- Verify `metamodule=1` in `module.prop`
- Check KSU version supports WebUI

## 🔗 Community

<div align="center">
  <h3>
    <a href="https://t.me/mastermindszs">
      💬 @mastermindszs on Telegram
    </a>
  </h3>
  <p>Join for updates, support, and discussion</p>
</div>

## 📝 License

GPL-2.0

## 👤 Author

**爪卂丂ㄒ乇尺爪工刀ᗪ丂 (Mastermind)**

- GitHub: [@mafiadan6](https://github.com/mafiadan6)
- Telegram: [@mastermindszs](https://t.me/mastermindszs)

## 📦 Version

v2.0.0 — Initial Release
