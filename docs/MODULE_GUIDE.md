# Module Usage Guide

## Installation

1. Download `MountZero-Manager-v2.0.0-FLASHABLE.zip`
2. Open KernelSU app → Modules → Install from storage
3. Select the zip file
4. Reboot device

## Post-Installation

After reboot:
- MountZero VFS engine starts automatically
- Modules are scanned and redirect rules created
- WebUI is available in KernelSU manager
- Bootloop guard is active (3 failures → skip mount)

## WebUI Usage

### Status Tab
- View system info, engine status, capabilities
- Enable/disable VFS engine

### Modules Tab
- List all installed modules with active/disabled status
- Search/filter modules

### VFS Rules Tab
- View active redirect rules
- Add new rules: virtual path → real path
- Delete individual rules
- Clear all rules

### Config Tab
- **Mount Settings**: Mount engine selection, extra partitions, SELinux spoof, mount hiding
- **SUSFS Bridge**: Hidden paths, hidden maps, cmdline spoofing
- **Uname Spoofing**: Custom release/version strings, auto-spoof toggle at boot
- **ADB Root**: Toggle ADB root access with persistence

### Guard Tab
- View bootloop guard ring display
- Check boot count and threshold
- Set new threshold (1-10)
- Reset guard after recovery

### Tools Tab
- **Diagnostics**: Detect kernel capabilities, create diagnostic dump
- **BBR**: Toggle BBR congestion control (persists across reboots)
- **Module Operations**: Manual module install, scan all modules

## CLI Usage

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

## Configuration Files

All configs stored in `/data/adb/mountzero/`:

```
/data/adb/mountzero/
├── config.toml              # Main configuration
├── custom_sus_path.txt      # Custom SUSFS paths to hide
├── custom_sus_map.txt       # Custom SUSFS maps to hide
├── bbr_enabled              # BBR toggle state (1 or 0)
├── adb_root                 # ADB root toggle state (true or false)
├── uname_spoof_enabled      # Uname auto-spoof toggle state (1 or 0)
├── uname_release              # Custom uname release string
├── uname_version              # Custom uname version string
├── .bootcount               # Bootloop guard counter
└── logs.txt                 # Hiding engine logs
```

## Module Structure

```
/data/adb/modules/mountzero_vfs/
├── bin/
│   ├── mzctl                # CLI binary (783KB)
│   └── susfs                # SUSFS CLI binary (23KB)
├── webroot/
│   ├── index.html           # WebUI main page
│   ├── styles.css           # Dark glassmorphism theme
│   ├── script.js            # WebUI controller
│   └── assets/
│       └── kernelsu.js      # KernelSU JS SDK
├── customize.sh             # Installation script
├── post-fs-data.sh          # Early boot script
├── service.sh               # Hot-plug daemon + boot-time config
├── metamount.sh             # Metamodule mount hook
├── metainstall.sh           # Hot module install handler
├── hiding.sh                # BRENE hiding engine
├── bridge.sh                # SUSFS bridge reconciler
├── axon.sh                  # ADB root injection
├── config.sh                # Config manager
├── sepolicy.rule            # SELinux policy rules
├── module.prop              # Module metadata
└── custom_sus_*.txt         # Custom SUSFS configs
```

## Uninstall

1. Open KernelSU app → Modules → MountZero VFS
2. Tap the remove button
3. Reboot device

Or manually:
```bash
adb shell su
touch /data/adb/modules/mountzero_vfs/remove
reboot
```

## Troubleshooting

### Binary not found errors
- Check `/data/adb/ksu/bin/mzctl` exists
- If missing, the module's `customize.sh` failed to copy it
- Reinstall the module

### WebUI not loading
- Check module files: `ls /data/adb/modules/mountzero_vfs/webroot/`
- Verify `metamodule=1` in `module.prop`
- Check KSU version supports WebUI

### Modules not scanning
- Check `dmesg | grep mountzero` for errors
- Verify `/dev/mountzero` exists
- Ensure `CONFIG_KSU_SUSFS=y` is enabled
- Ensure MountZero Manager module is installed

### BBR not enabling
- Check kernel config: `cat /proc/sys/net/ipv4/tcp_available_congestion_control`
- BBR must be compiled into kernel (`CONFIG_TCP_CONG_BBR=y`)
- Check `dmesg | grep mountzero` for BBR errors
