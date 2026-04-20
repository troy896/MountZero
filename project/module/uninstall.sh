#!/system/bin/sh
# MountZero VFS - Uninstall Script
# Called when module is being removed via KSU manager.
# Cleans up overlay mounts, VFS rules, and all data.

MZCTL="/data/adb/ksu/bin/mzctl"
WORK_BASE="/dev/mountzero_work"
UPPER_BASE="/dev/mountzero_upper"

# Clear all VFS rules
if [ -x "$MZCTL" ]; then
    $MZCTL clear 2>/dev/null
    $MZCTL disable 2>/dev/null
fi

# Unmount all mountzero overlay mounts
grep "mountzero_" /proc/mounts 2>/dev/null | while read -r line; do
    local mp
    mp=$(echo "$line" | awk '{print $2}')
    umount -l "$mp" 2>/dev/null
done

# Clean work/upper directories
rm -rf "$WORK_BASE" 2>/dev/null
rm -rf "$UPPER_BASE" 2>/dev/null

# Remove data directory
rm -rf /data/adb/mountzero 2>/dev/null

# Remove mzctl from KSU bin
rm -f /data/adb/ksu/bin/mzctl 2>/dev/null

# Remove lock files
rm -f /dev/mountzero_metamount_lock 2>/dev/null
rm -f /dev/mountzero_mount_lock 2>/dev/null

exit 0
