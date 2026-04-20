#!/system/bin/sh
# MountZero VFS - Meta Uninstall Script
# Called when metamodule is being removed.

# Clear VFS rules if mzctl is available
if [ -x /data/adb/ksu/bin/mzctl ]; then
    /data/adb/ksu/bin/mzctl clear 2>/dev/null
    /data/adb/ksu/bin/mzctl disable 2>/dev/null
fi

# Remove data directory
rm -rf /data/adb/mountzero 2>/dev/null

# Remove mzctl from KSU bin
rm -f /data/adb/ksu/bin/mzctl 2>/dev/null

exit 0
