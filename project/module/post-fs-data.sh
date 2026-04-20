#!/system/bin/sh
# MountZero VFS - Post-FS-Data Script
# This runs AFTER metamount.sh has completed the mount pipeline.
# Handles bootloop guard recording, ADB root setup, and core hiding at early boot.

MODDIR="${0%/*}"
HIDING_SH="$MODDIR/hiding.sh"
CONFIG_FILE="/data/adb/mountzero/config.toml"

# Get config value - wait for filesystem to settle
get_config() {
    local section="$1" key="$2" default="$3"
    sleep 1
    if [ -f "$CONFIG_FILE" ]; then
        local val=$(grep -A50 "^\[$section\]" "$CONFIG_FILE" 2>/dev/null | grep "^$key" | head -1 | cut -d'=' -f2 | tr -d ' "\r\n')
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

# Record post-fs-data execution for bootloop detection
echo 1 > /data/adb/mountzero/.bootcount 2>/dev/null

# Enable MountZero VFS (safety net if metamount.sh didn't)
/data/adb/ksu/bin/mzctl enable 2>/dev/null

# Apply core hiding at early boot - based on config toggles
# Only applies if user has enabled those features in WebUI settings

if [ "$(get_config brene hideModuleInjections false)" = "true" ]; then
    $MODDIR/hiding.sh injections 2>/dev/null &
fi

if [ "$(get_config brene nonStandardSdcardPathsHiding false)" = "true" ]; then
    $MODDIR/hiding.sh sdcard 2>/dev/null &
fi

if [ "$(get_config brene hideRecovery false)" = "true" ]; then
    $MODDIR/hiding.sh recovery 2>/dev/null &
fi

if [ "$(get_config brene hideMounts false)" = "true" ]; then
    $MODDIR/hiding.sh mounts 2>/dev/null &
fi

exit 0