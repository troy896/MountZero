# MountZero VFS

<p align="center">
  <strong>🔥 VFS-level path redirection + SUSFS root evasion for KernelSU/ReSukiSU</strong>
</p>

<p align="center">
  <a href="https://github.com/mafiadan6/MountZero/releases"><img src="https://img.shields.io/badge/Download-v2.0.0-blue?style=for-the-badge&logo=github" alt="Download"></a>
  <a href="https://t.me/mountzerozvfs)"><img src="https://img.shields.io/badge/Telegram-@mastermindszs-2CA5E0?style=for-the-badge&logo=telegram" alt="Telegram"></a>
  <a href="https://github.com/mafiadan6/MountZero/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-GPL--2.0-green?style=for-the-badge" alt="License"></a>
</p>

---

## 📖 Overview

MountZero VFS is a **built-in kernel module** that provides VFS-level path redirection for KernelSU/ReSukiSU modules. It works alongside **SUSFS v2.1.0** to deliver complete root hiding and module management without traditional overlay mounts.

### How It Works

Traditional root solutions use overlayfs to mount module files over the system partition. MountZero intercepts file lookups at the VFS layer and redirects them transparently — **zero mounts, zero /proc/mounts entries, zero detection surface**.

### Key Features

- **VFS Path Redirection** — transparent file redirection at the VFS layer using hash table + bloom filter
- **Auto Module Scanning** — recursively scans `/data/adb/modules/` and `/data/local/` at boot
- **Hot-Plug Detection** — watches for new modules every 5 seconds without reboot
- **SUSFS Integration** — full bridge to all 9 SUSFS features (path hiding, mount hiding, kstat spoofing, uname spoofing, cmdline spoofing, maps hiding, logging, symbol hiding, open redirect)
- **BRENE Root Evasion** — path hiding, maps hiding, properties spoofing, cmdline/bootconfig spoofing
- **Bootloop Guard** — automatically skips mount pipeline after 3 failed boots
- **BBR Congestion Control** — toggle BBR at boot with persistence
- **WebUI Management** — 6-tab KernelSU WebUI (Status, Modules, Rules, Config, Guard, Tools)
- **ADB Root** — toggle ADB root access with persistence

---

## 📦 Module Download

> **⚠️ Required:** You MUST install the MountZero Manager module for the VFS driver to work.  
> The kernel patch adds the driver — the module provides the WebUI, mounting scripts, and management layer.

<div align="center">
  <h3>
    <a href="https://github.com/mafiadan6/MountZero/releases">
      📥 Download MountZero Manager v2.0.0
    </a>
  </h3>
  <p><em>Flash via KernelSU → Modules → Install from storage</em></p>
</div>

---

## 🚀 Quick Start

### ⚠️ Important: MountZero vs ZeroMount

| Project | Target Kernel | Description |
|---------|--------------|-------------|
| **MountZero** (this repo) | **4.14 kernels** (also works on **5.x/6.x** with minor modifications) | VFS path redirection + SUSFS bridge for KernelSU, ReSukiSU, and other built-in root solutions. **Tested with ReSukiSU.** |
| **ZeroMount** | **5.x/6.x GKI kernels** | Full SUSFS + VFS solution via [Super-Builders](https://github.com/Enginex0/Super-Builders) 💬 [Join Super Powers](https://t.me/superpowers9) |

> **⚠️ Important:** This repository does NOT include SUSFS patches. Your 4.14 kernel must already have SUSFS v2.1.0 (`CONFIG_KSU_SUSFS=y`) and **KernelSU or ReSukiSU** integrated. APatch is NOT supported.

> **Want to use MountZero on 5.x/6.x kernels?** You absolutely can! The source files (`fs/mountzero.c`, `fs/mountzero_vfs.c`, headers) are included in this repository under `kernel/source_files/`. Simply copy them to your kernel tree, update `fs/Makefile` and `fs/Kconfig`, and hook into `fs/namei.c`. The `patch_kernel.sh` script auto-detects the correct hook location for most kernel versions. See the [Kernel Integration Guide](docs/KERNEL_INTEGRATION.md) for detailed instructions.
> 
> **If you prefer a pre-patched solution for GKI kernels:** Use [ZeroMount via Super-Builders](https://github.com/Enginex0/Super-Builders) instead.

### How to Integrate MountZero into 5.x/6.x Kernels

If you have a 5.x or 6.x kernel that already has SUSFS 2.1.0 and KernelSU integrated, you can add MountZero in just 4 steps:

**1. Copy source files to your kernel tree:**
```bash
cd /path/to/your/kernel/source
cp /path/to/MountZero_Project/kernel/source_files/fs/mountzero.c fs/
cp /path/to/MountZero_Project/kernel/source_files/fs/mountzero_vfs.c fs/
cp /path/to/MountZero_Project/kernel/source_files/include/linux/mountzero*.h include/linux/
```

**2. Update `fs/Makefile`:**
```makefile
obj-$(CONFIG_MOUNTZERO)		+= mountzero.o mountzero_vfs.o
```

**3. Update `fs/Kconfig`:**
```kconfig
config MOUNTZERO
    bool "MountZero VFS Path Redirection System"
    depends on KSU_SUSFS
    default y
    help
      VFS-level path redirection for KernelSU modules.
```

**4. Hook into `fs/namei.c`:**

Find the `getname_flags()` function (or equivalent path resolution function in your kernel version) and add this hook before the function returns:

```c
#ifdef CONFIG_MOUNTZERO
    /* MountZero VFS path redirection */
    result = mountzero_vfs_getname_hook(result);
#endif
```

Also add the include near the top of `fs/namei.c`:
```c
#ifdef CONFIG_MOUNTZERO
#include <linux/mountzero_vfs.h>
#endif
```

**5. Enable in defconfig:**
```text
CONFIG_MOUNTZERO=y
```

**6. Build and flash.** The `patch_kernel.sh` script in this repo automates steps 1-4 for most kernels.

> **Note:** The only kernel-version-specific change is the `fs/namei.c` hook location. The `getname_flags()` function structure is consistent across 4.14–6.x kernels, but if your kernel has a different path resolution structure, you may need to place the hook in `filename_lookup()` or `path_lookupat()` instead.

### Step 0: Apply SUSFS Patches (4.14 Kernels Only)

> **⚠️ Important:** This repository does NOT include SUSFS patches. Your 4.14 kernel must already have SUSFS v2.1.0 (`CONFIG_KSU_SUSFS=y`) and **KernelSU or ReSukiSU** integrated.

If your 4.14 kernel doesn't have SUSFS, you'll need to port the SUSFS patches manually from the [Super-Builders repository](https://github.com/Enginex0/Super-Builders). The GKI patches in that repo won't apply directly to 4.14 kernels due to code differences.

**Also required:** KernelSU or ReSukiSU must be integrated first. See [KernelSU docs](https://kernelsu.org).

### Step 1: Apply MountZero VFS Patches

```bash
cd MountZero_Project
./scripts/patch_kernel.sh /path/to/kernel/source
```

### Step 2: Configure Kernel

Add to your defconfig:

```text
# SUSFS v2.1.0 (must already be set)
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

### Step 3: Build & Flash

```bash
# Build kernel
make -j$(nproc)

# Flash kernel (method depends on device)
fastboot flash boot boot.img

# Flash MountZero Manager module via KernelSU
# 📥 Download: https://github.com/mafiadan6/MountZero/releases

# Reboot
```

---

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
│  susfs (add-path, add-map, set-uname, reset-uname,      │
│           hide-mounts, log, avc, cmdline, version,      │
│           features), guard, detect, dump                │
└──────────────────────┬──────────────────────────────────┘
                       │ IOCTL on /dev/mountzero
                       ▼
┌─────────────────────────────────────────────────────────┐
│              Kernel (fs/mountzero.c)                    │
│  ├─ VFS path redirection (hash table + bloom filter)    │
│  ├─ Auto module scanner (late_initcall_sync)            │
│  ├─ Hot-plug kernel thread (5s polling)                 │
│  ├─ SUSFS bridge (all 9 features via supercall)         │
│  ├─ Direct uname spoofing (bypasses SUSFS binary bug)   │
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

---

## 📂 Project Structure

```
MountZero_Project/
├── README.md                          # This file
├── LICENSE                            # GPL-2.0 license
├── kernel/
│   ├── patches/
│   │   └── 003_mountzero_vfs.patch    # MountZero VFS kernel patch template
│   └── source_files/
│       ├── fs/
│       │   ├── mountzero.c            # Core VFS driver (~1400 lines)
│       │   ├── mountzero_vfs.c        # VFS hooks (~300 lines)
│       │   └── mountzero_cli.c        # Userspace CLI source (~1000 lines)
│       └── include/linux/
│           ├── mountzero.h            # Public IOCTL interface
│           ├── mountzero_def.h        # Internal definitions
│           └── mountzero_vfs.h        # VFS hook declarations
├── module/
│   └── MountZero-Manager-v2.0.0-FLASHABLE.zip
├── scripts/
│   └── patch_kernel.sh                # One-command kernel patcher
└── docs/
    ├── KERNEL_INTEGRATION.md          # Detailed kernel patching guide
    └── MODULE_GUIDE.md                # Module usage guide
```

---

## ⚙️ Configuration

### MountZero VFS Config

| Config | Default | Description |
|--------|---------|-------------|
| `CONFIG_MOUNTZERO` | `y` | Enable MountZero VFS driver |
| Depends on | `KSU_SUSFS` | Requires SUSFS to be enabled |

### Kernel Integration Details

| Component | Details |
|-----------|---------|
| **Driver registration** | `/dev/mountzero` misc device (dynamic minor) |
| **Sysfs entries** | `/sys/kernel/mountzero/mz_version`, `/sys/kernel/mountzero/mz_status`, `/sys/kernel/mountzero/mz_guard_count`, `/sys/kernel/mountzero/mz_guard_threshold` |
| **VFS hooks** | `fs/namei.c` → `mountzero_vfs_getname_hook()` in path resolution |
| **Rule storage** | Hash table (1024 buckets) + 8192-bit bloom filter for O(1) lookups |
| **Module scanner** | Runs at `late_initcall_sync`, scans `/data/adb/modules/` and `/data/local/` |
| **Hot-plug thread** | Kernel thread polling every 5 seconds for new modules |
| **Bootloop guard** | Stored in `/data/adb/mountzero/.bootcount`, skips mount after 3 failures |

### SUSFS Features Integration

All 9 SUSFS features are accessible through MountZero:

| SUSFS Feature | Kernel Config | MountZero Access |
|---------------|--------------|------------------|
| Path Hiding | `CONFIG_KSU_SUSFS_SUS_PATH` | `mzctl susfs add-path`, `bridge.sh` |
| Mount Hiding | `CONFIG_KSU_SUSFS_SUS_MOUNT` | `mzctl susfs hide-mounts`, `hiding.sh` |
| Kstat Spoofing | `CONFIG_KSU_SUSFS_SUS_KSTAT` | `mzctl susfs add-kstat`, `hiding.sh` |
| Uname Spoofing | `CONFIG_KSU_SUSFS_SPOOF_UNAME` | `mzctl susfs set-uname`, WebUI Config tab |
| Kernel Logging | `CONFIG_KSU_SUSFS_ENABLE_LOG` | `mzctl susfs log enable/disable`, `hiding.sh` |
| Symbol Hiding | `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | Built-in (kernel hides SUSFS symbols) |
| Cmdline Spoofing | `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` | `mzctl susfs cmdline <file>`, `hiding.sh` |
| Open Redirect | `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | Built-in (SUSFS handles open redirection) |
| Maps Hiding | `CONFIG_KSU_SUSFS_SUS_MAP` | `mzctl susfs add-map`, `hiding.sh` |

---

## 🔧 WebUI Features

### 6 Tabs in KernelSU Manager

| Tab | Features |
|-----|----------|
| **Status** | System info (kernel, Android, device, uptime, SELinux), Engine status (VFS rules, SUSFS paths/maps, blocked UIDs), Capabilities (VFS driver, SUSFS, OverlayFS, EROFS), VFS enable/disable buttons |
| **Modules** | List all installed modules with active/disabled status, search/filter |
| **VFS Rules** | View active redirect rules, add new rules (virtual → real path), delete rules, clear all rules |
| **Config** | Mount engine selection, extra partitions, SUSFS hidden paths/maps, uname spoofing with auto-spoof toggle at boot, SELinux spoof toggle, ADB root toggle, save/reset config |
| **Guard** | Bootloop guard ring display, boot count, threshold status, set new threshold, check/reset guard |
| **Tools** | Kernel capability detection, diagnostic dump, BBR congestion control toggle, module operations (install, scan) |

### Uname Spoofing

- **Auto-spoof toggle** — when enabled, spoofs at boot with hardcoded default (`5.14.113-g9f6a47a`) or custom values
- **Custom values** — set any release/version string via WebUI
- **Reset to Stock** — restores real kernel version via `susfs set_uname default default`
- **Persistence** — saved values survive reboots

### BBR Congestion Control

- **Toggle switch** — enables BBR (`net.core.default_qdisc=fq`, `net.ipv4.tcp_congestion_control=bbr`)
- **Status display** — shows current algorithm, BBR availability
- **Persistence** — saves state to `/data/adb/mountzero/bbr_enabled`, applied at boot by `service.sh`

### ADB Root

- **Toggle** — enables ADB root access via `setprop service.adb.root 1 && stop/start adbd`
- **Persistence** — saves state to `/data/adb/mountzero/adb_root`, applied at boot by `service.sh`

---

## 🛠️ CLI Usage

```bash
# Get into root shell
adb shell su

# Basic commands
mzctl version                    # Show Mountzero version
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
mzctl susfs add-path /data/adb/ksu           # Add hidden path
mzctl susfs add-path-loop /data/adb/modules   # Add hidden path (loop detection)
mzctl susfs add-map /data/adb/modules/X/zygisk.so  # Add hidden map
mzctl susfs set-uname '4.14.113-g9f6a47a' '#1 SMP PREEMPT Mon Oct 6 16:50:48 UTC 2025'  # Spoof uname
mzctl susfs reset-uname                       # Restore actual kernel version
mzctl susfs hide-mounts 1                     # Hide SUSFS mounts from non-su processes
mzctl susfs log enable                        # Enable SUSFS kernel logging
mzctl susfs avc enable                        # Enable AVC log spoofing
mzctl susfs cmdline /data/adb/mountzero/fake_cmdline.txt  # Spoof cmdline
mzctl susfs version                           # Show SUSFS version
mzctl susfs features                          # Show SUSFS features

# Bootloop guard
mzctl guard check                        # Check guard status
mzctl guard recover                      # Reset guard after recovery

# Diagnostics
mzctl detect                             # Detect kernel capabilities
mzctl dump                               # Create diagnostic dump
```

---

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

---

## 🤝 Credits & Community

This project was built to bring VFS-level path redirection to 4.14 kernels. Massive appreciation to the teams behind the foundational tools that made this possible:

- **[Super-Builders](https://github.com/Enginex0/Super-Builders)** – For the incredible work on SUSFS v2.1.0, ZeroMount, and the GKI patch ecosystem. Their work is the absolute foundation of modern Android root hiding. Huge thanks to the team for pushing the boundaries of what's possible.  
  💬 **Join their community:** [Super Powers Telegram](https://t.me/superpowers9)
- **[KernelSU](https://kernelsu.org)** – For the root framework and WebUI integration
- **[ReSukiSU](https://github.com/ReSukiSU)** – Tested root framework with SUSFS integration

---

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

---

## 📝 License

GPL-2.0

## 👤 Author & Contact

**爪卂丂ㄒ乇尺爪工刀ᗪ丂 (Mastermind)**

- GitHub: [@mafiadan6](https://github.com/mafiadan6)
- Telegram: [@bitcockiii](https://t.me/bitcockiii)

## 📦 Version

v2.0.0 — Complete Release
