# Module Usage Guide

## Installation

1. Flash the kernel with MountZero VFS enabled
2. Flash `MountZero-Manager-v2.0.0-FLASHABLE.zip` via KernelSU
3. Reboot device

## After Boot

MountZero automatically:
- Scans `/data/adb/modules/` for KernelSU modules
- Scans `/data/local/` for custom modules (Droidspaces, etc.)
- Creates VFS redirect rules for all module files
- Applies BRENE hiding engine (path/map/prop spoofing)

## WebUI Management

Open KernelSU → MountZero module → WebUI tab

### Status Tab
- **System Info**: Kernel version, Android version, device model, uptime, SELinux status
- **Enchanted SUSFS VFS**: VFS status, SUSFS version, rule counts, SUSFS paths/maps
- **Capabilities**: VFS driver, SUSFS, OverlayFS, EROFS availability
- **Controls**: Enable/disable VFS engine, refresh status

### Modules Tab
- Lists all installed KernelSU modules
- Shows active/disabled status
- Search/filter modules

### VFS Rules Tab
- View all active redirect rules
- Add new rules: virtual path → real path
- Delete individual rules
- Clear all rules

### Config Tab
- **Mount Settings**: Mount engine (VFS/overlay/magic), extra partitions, SELinux spoof, mount hiding
- **SUSFS Bridge**: Hidden paths, hidden maps, uname spoofing
- **ADB Root**: Enable ADB root access via axon injection
- Save/reset config

### Guard Tab
- Bootloop guard status
- Boot count and threshold
- Reset guard after recovery

### Tools Tab
- **Diagnostics**: Detect kernel capabilities, create diagnostic dump
- **Module Operations**: Manual module install, scan all modules

## CLI Usage

```bash
# Get into shell
adb shell su

# Basic commands
mzctl version
mzctl status
mzctl enable
mzctl disable

# Rule management
mzctl add /system/bin/su /data/adb/modules/X/system/bin/su
mzctl del /system/bin/su
mzctl list
mzctl clear

# Module management
mzctl module scan
mzctl module install mymodule /data/adb/modules/mymodule
mzctl module install Droidspaces /data/local/Droidspaces custom

# SUSFS operations
mzctl susfs add-path /data/adb/ksu
mzctl susfs add-map /data/adb/modules/X/zygisk.so
mzctl susfs set-uname "4.14.356" "#1 SMP PREEMPT"
mzctl susfs version
mzctl susfs features

# Bootloop guard
mzctl guard check
mzctl guard recover

# Diagnostics
mzctl detect
mzctl dump
```

## Configuration Files

All configs stored in `/data/adb/mountzero/`:

```
/data/adb/mountzero/
├── config.toml           # Main configuration
├── custom_sus_path.txt   # Custom SUSFS paths to hide
├── custom_sus_map.txt    # Custom SUSFS maps to hide
├── logs.txt              # Hiding engine logs
└── .bootcount            # Bootloop counter
```

### config.toml Example

```toml
[mount]
mountEngine = "vfs"
mountSource = "KSU"
partitions = ["product", "system_ext", "vendor"]

[susfs]
enabled = true
pathHide = true
mapsHide = true
kstat = true
susfsLog = false
avcLogSpoofing = false

[brene]
verifiedBootHash = ""
kernelUmount = true
hideSusMounts = true
forceHideLsposed = true
spoofCmdline = true
hideKsuLoops = true
propSpoofing = true
autoHideInjections = true

[guard]
enabled = true
bootTimeout = 120
markerThreshold = 3

[perf]
enabled = true

[adb]
adbRoot = false
```

## BRENE Hiding Engine

The BRENE (Built-in Root Evasion Neutralization Engine) provides:

### Path Hiding
Hides files/directories from `readdir` and path lookups for unprivileged apps:
- `/data/adb/ksu/` - KSU binary
- `/data/adb/modules/` - Module directory
- `/data/local/tmp/` - Temp files
- Custom paths via `custom_sus_path.txt`

### Maps Hiding
Hides library mappings from `/proc/PID/maps`:
- Zygisk injection libraries
- LSPosed dex2oat paths
- Custom maps via `custom_sus_map.txt`

### Properties Spoofing
Spoofs 20+ Android system properties:
- `ro.secure=1`, `ro.debuggable=0` - Hide root
- `ro.boot.flash.locked=1` - Locked bootloader
- `ro.boot.verifiedbootstate=green` - Green boot state
- `ro.build.type=user` - User build (not userdebug)

### Uname Spoofing
Returns stock kernel version via `uname`:
- `uname -r` → Stock version string
- `uname -v` → Stock build string

### Cmdline Spoofing
Modifies `/proc/cmdline` to show clean boot state:
- `androidboot.verifiedbootstate=green`
- `androidboot.vbmeta.device_state=locked`

## Hot-Plug Detection

MountZero runs a background daemon that:
1. Polls `/data/adb/modules_update/` every 5 seconds
2. Polls `/data/local/` for new custom modules
3. Automatically installs and scans new modules
4. No reboot required for new modules

## Uninstall

1. Remove module via KernelSU
2. Or manually: `touch /data/adb/modules/mountzero_vfs/remove`
3. Reboot device
