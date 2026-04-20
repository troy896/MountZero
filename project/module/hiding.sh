#!/system/bin/sh
# MountZero VFS - SUSFS Hiding Engine (BRENE Integration)
# Provides root evasion: path hiding, maps hiding, prop spoofing, cmdline spoofing
# All features from BRENE integrated directly into MountZero

PERSISTENT_DIR="/data/adb/mountzero"
CONFIG_FILE="$PERSISTENT_DIR/config.toml"
SUSFS_BIN="/data/adb/ksu/bin/susfs"
RESETPROP="/data/adb/ksu/bin/resetprop"
LOG_FILE="$PERSISTENT_DIR/logs.txt"

config_get() {
    local section="$1"
    local key="$2"
    local default="${3:-}"
    [ ! -f "$CONFIG_FILE" ] && echo "$default" && return
    grep -i "^[[:space:]]*$key[[:space:]]*=" "$CONFIG_FILE" 2>/dev/null | grep -i "$section" >/dev/null && \
        grep -A1 -i "[$section]" "$CONFIG_FILE" | grep -i "^[[:space:]]*$key=" | cut -d'=' -f2- | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' || echo "$default"
}

# Fallback to ksu_susfs if susfs not available
if [ ! -x "$SUSFS_BIN" ]; then
    SUSFS_BIN="/data/adb/ksu/bin/ksu_susfs"
fi

log() {
    echo "mountzero-hiding: $*" > /dev/kmsg 2>/dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
}

susfs_clone_perm() {
    local TO="$1"
    local FROM="$2"
    if [ -z "$TO" ] || [ -z "$FROM" ]; then
        return
    fi
    local CLONED_PERM_STRING
    CLONED_PERM_STRING=$(stat -c "%a %U %G" "$FROM" 2>/dev/null)
    if [ -n "$CLONED_PERM_STRING" ]; then
        set $CLONED_PERM_STRING
        chmod $1 "$TO" 2>/dev/null
        chown $2:$3 "$TO" 2>/dev/null
        busybox chcon --reference="$FROM" "$TO" 2>/dev/null
    fi
}

# ============================================================
# Phase 1: Path Hiding (sus_path)
# ============================================================

apply_sus_paths() {
    log "Applying SUSFS path hiding rules"

    # KSU/APatch paths
    susfs_add_path "/data/adb/ksu"
    susfs_add_path "/data/adb/ap"
    susfs_add_path "/data/adb/modules"
    susfs_add_path "/data/adb/modules_update"

    # Magisk paths
    susfs_add_path "/sbin/.magisk"
    susfs_add_path "/data/cache/magisk.log"
    susfs_add_path "/cache/recovery"

    # Common detection paths
    susfs_add_path "/data/local/tmp"
    susfs_add_path "/data/adb/mountzero"

    # Custom user-defined paths
    if [ -f "$PERSISTENT_DIR/custom_sus_path.txt" ]; then
        while IFS= read -r path; do
            path=$(echo "$path" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            [ -z "$path" ] && continue
            susfs_add_path "$path"
        done < "$PERSISTENT_DIR/custom_sus_path.txt"
    fi

    log "SUSFS path hiding applied"
}

susfs_add_path() {
    local path="$1"
    if [ -e "$path" ]; then
        $SUSFS_BIN add_sus_path "$path" 2>/dev/null && \
            log "[sus_path]: $path" || \
            log "[sus_path FAILED]: $path"
    fi
}

susfs_add_path_loop() {
    local path="$1"
    if [ -e "$path" ]; then
        $SUSFS_BIN add_sus_path_loop "$path" 2>/dev/null && \
            log "[sus_path_loop]: $path" || \
            log "[sus_path_loop FAILED]: $path"
    fi
}

# ============================================================
# Phase 2: Maps Hiding (sus_map)
# ============================================================

apply_sus_maps() {
    log "Applying SUSFS maps hiding rules"

    # Zygisk injection hiding
    susfs_add_map "/data/adb/modules/rezygisk/zygisk"
    susfs_add_map "/data/adb/modules/rezygisk/lib64/libzygisk.so"
    susfs_add_map "/data/adb/modules/rezygisk/lib/libzygisk.so"
    susfs_add_map "/data/adb/modules/zygisk_lsposed"
    susfs_add_map "/data/adb/modules/zygisk-detach/zygisk"

    # Custom user-defined maps
    if [ -f "$PERSISTENT_DIR/custom_sus_map.txt" ]; then
        while IFS= read -r path; do
            path=$(echo "$path" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            [ -z "$path" ] && continue
            susfs_add_map "$path"
        done < "$PERSISTENT_DIR/custom_sus_map.txt"
    fi

    log "SUSFS maps hiding applied"
}

susfs_add_map() {
    local path="$1"
    if [ -e "$path" ]; then
        $SUSFS_BIN add_sus_map "$path" 2>/dev/null && \
            log "[sus_map]: $path" || \
            log "[sus_map FAILED]: $path"
    fi
}

# ============================================================
# Phase 3: Uname Spoofing
# ============================================================
# Only auto-spoof at boot if user enabled the toggle in WebUI.
# Uses hardcoded default values that look like a stock kernel.
# ============================================================

apply_uname_spoofing() {
    local ENABLED_FILE="/data/adb/mountzero/uname_spoof_enabled"

    if [ ! -f "$ENABLED_FILE" ]; then
        log "Skipping automatic uname spoofing (not enabled by user)"
        return
    fi

    if [ "$(cat "$ENABLED_FILE" 2>/dev/null)" != "1" ]; then
        log "Skipping automatic uname spoofing (disabled by user)"
        return
    fi

    log "Applying automatic uname spoofing at boot"

    # Hardcoded default spoofed values (stock-looking kernel version)
    local kernel_release="5.14.113-g9f6a47a"
    local kernel_version
    local _d
    _d=$(date '+%a %b %d %H:%M:%S UTC %Y')
    kernel_version="#1 SMP PREEMPT $_d"

    # Check for custom values
    if [ -f "/data/adb/mountzero/uname_release" ]; then
        kernel_release=$(cat /data/adb/mountzero/uname_release 2>/dev/null)
    fi
    if [ -f "/data/adb/mountzero/uname_version" ]; then
        kernel_version=$(cat /data/adb/mountzero/uname_version 2>/dev/null)
    fi

    $SUSFS_BIN set_uname "$kernel_release" "$kernel_version" 2>/dev/null && \
        log "[set_uname]: $kernel_release $kernel_version" || \
        log "[set_uname FAILED]"
}

# ============================================================
# Phase 4: Cmdline/Bootconfig Spoofing
# ============================================================

apply_cmdline_spoofing() {
    log "Applying cmdline/bootconfig spoofing"

    local susfs_variant
    susfs_variant=$($SUSFS_BIN show variant 2>/dev/null)

    if [ "$susfs_variant" = "GKI" ]; then
        local FAKE_BOOTCONFIG="$PERSISTENT_DIR/fake_bootconfig.txt"
        cat /proc/bootconfig > "$FAKE_BOOTCONFIG" 2>/dev/null
        sed -i 's/androidboot.warranty_bit = "1"/androidboot.warranty_bit = "0"/' "$FAKE_BOOTCONFIG" 2>/dev/null
        sed -i 's/androidboot.verifiedbootstate = "orange"/androidboot.verifiedbootstate = "green"/' "$FAKE_BOOTCONFIG" 2>/dev/null
        sed -i 's/androidboot.vbmeta.device_state = "unlocked"/androidboot.vbmeta.device_state = "locked"/' "$FAKE_BOOTCONFIG" 2>/dev/null
        $SUSFS_BIN set_cmdline_or_bootconfig "$FAKE_BOOTCONFIG" 2>/dev/null && \
            log "[set_cmdline]: bootconfig spoofed" || \
            log "[set_cmdline FAILED]"
    else
        local FAKE_CMDLINE="$PERSISTENT_DIR/fake_cmdline.txt"
        cat /proc/cmdline > "$FAKE_CMDLINE" 2>/dev/null
        sed -i 's/androidboot.warranty_bit=1/androidboot.warranty_bit=0/' "$FAKE_CMDLINE" 2>/dev/null
        sed -i 's/androidboot.verifiedbootstate=orange/androidboot.verifiedbootstate=green/' "$FAKE_CMDLINE" 2>/dev/null
        sed -i 's/androidboot.vbmeta.device_state=unlocked/androidboot.vbmeta.device_state=locked/' "$FAKE_CMDLINE" 2>/dev/null
        $SUSFS_BIN set_cmdline_or_bootconfig "$FAKE_CMDLINE" 2>/dev/null && \
            log "[set_cmdline]: cmdline spoofed" || \
            log "[set_cmdline FAILED]"
    fi
}

# ============================================================
# Phase 5: Mount Hiding
# ============================================================

apply_mount_hiding() {
    log "Applying mount hiding"

    # Hide SUSFS mounts from non-su processes
    $SUSFS_BIN hide_sus_mnts_for_non_su_procs 1 2>/dev/null && \
        log "[hide_mounts]: enabled for non-su processes" || \
        log "[hide_mounts FAILED]"
}

# ============================================================
# Phase 6: AVC Log Spoofing
# ============================================================

apply_avc_log_spoofing() {
    local avc_enabled
    avc_enabled=$(config_get "susfs" "avcLogSpoofing" "false")
    if [ "$avc_enabled" != "true" ]; then
        log "[avc_log_spoofing]: disabled in config"
        return
    fi
    log "Applying AVC log spoofing"

    $SUSFS_BIN enable_avc_log_spoofing 1 2>/dev/null && \
        log "[avc_log_spoofing]: enabled" || \
        log "[avc_log_spoofing FAILED]"
}

# ============================================================
# Phase 7: Android System Properties Spoofing
# ============================================================

apply_prop_spoofing() {
    log "Applying Android system properties spoofing"

    # Basic security props
    $RESETPROP -n "ro.adb.secure" "1" 2>/dev/null
    $RESETPROP -n "ro.debuggable" "0" 2>/dev/null
    $RESETPROP -n "ro.secure" "1" 2>/dev/null
    $RESETPROP -n "ro.build.selinux" "1" 2>/dev/null
    $RESETPROP -n "ro.build.type" "user" 2>/dev/null
    $RESETPROP -n "ro.build.tags" "release-keys" 2>/dev/null
    $RESETPROP -n "ro.bootmode" "normal" 2>/dev/null
    $RESETPROP -n "ro.bootimage.build.tags" "release-keys" 2>/dev/null

    # Bootloader/verified boot props
    $RESETPROP -n "ro.boot.flash.locked" "1" 2>/dev/null
    $RESETPROP -n "ro.boot.verifiedbootstate" "green" 2>/dev/null
    $RESETPROP -n "ro.boot.vbmeta.device_state" "locked" 2>/dev/null
    $RESETPROP -n "ro.boot.veritymode" "enforcing" 2>/dev/null
    $RESETPROP -n "ro.boot.vbmeta.hash_alg" "sha256" 2>/dev/null
    $RESETPROP -n "ro.boot.vbmeta.avb_version" "1.3" 2>/dev/null
    $RESETPROP -n "ro.boot.vbmeta.invalidate_on_error" "yes" 2>/dev/null
    $RESETPROP -n "ro.is_ever_orange" "0" 2>/dev/null
    $RESETPROP -n "vendor.boot.vbmeta.device_state" "locked" 2>/dev/null
    $RESETPROP -n "vendor.boot.verifiedbootstate" "green" 2>/dev/null

    # Warranty props
    $RESETPROP -n "ro.warranty_bit" "0" 2>/dev/null
    $RESETPROP -n "ro.vendor.boot.warranty_bit" "0" 2>/dev/null
    $RESETPROP -n "ro.vendor.warranty_bit" "0" 2>/dev/null
    $RESETPROP -n "ro.boot.warranty_bit" "0" 2>/dev/null
    $RESETPROP -n "sys.oem_unlock_allowed" "0" 2>/dev/null

    # Fix fingerprint to user (not userdebug)
    local fingerprint
    fingerprint=$($RESETPROP ro.build.fingerprint 2>/dev/null)
    if [ -n "$fingerprint" ]; then
        local fixed_fingerprint="${fingerprint//userdebug/user}"
        $RESETPROP -n "ro.build.fingerprint" "$fixed_fingerprint" 2>/dev/null
    fi

    # Delete props that shouldn't exist
    $RESETPROP --delete "ro.boot.verifiedbooterror" 2>/dev/null
    $RESETPROP --delete "ro.boot.verifyerrorpart" 2>/dev/null
    $RESETPROP --delete "crashrecovery.rescue_boot_count" 2>/dev/null

    log "Android system properties spoofed"
}

# ============================================================
# Phase 8: LSPosed Hiding
# ============================================================

apply_lsposed_hiding() {
    log "Applying LSPosed hiding"

    # Hide dex2oat paths
    susfs_add_map "/system/apex/com.android.art/bin/dex2oat"
    susfs_add_map "/system/apex/com.android.art/bin/dex2oat32"
    susfs_add_map "/system/apex/com.android.art/bin/dex2oat64"
    susfs_add_map "/apex/com.android.art/bin/dex2oat"
    susfs_add_map "/apex/com.android.art/bin/dex2oat32"
    susfs_add_map "/apex/com.android.art/bin/dex2oat64"

    log "LSPosed hiding applied"
}

# ============================================================
# Phase 9: Ext4 Loop/JBD2 Hiding
# ============================================================

apply_ext4_loop_hiding() {
    log "Applying ext4 loop/jbd2 hiding"

    # Hide ext4 loops and jbd2 journals
    for device in $(ls -Ld /proc/fs/jbd2/loop*8 2>/dev/null | sed 's|/proc/fs/jbd2/||; s|-8||'); do
        susfs_add_path "/proc/fs/jbd2/${device}-8"
        susfs_add_path "/proc/fs/ext4/${device}"
    done

    # Spoof nlink of /proc/fs/jbd2 to 2
    $SUSFS_BIN add_sus_kstat_statically '/proc/fs/jbd2' 'default' 'default' '2' 'default' 'default' 'default' 'default' 'default' 'default' 'default' 'default' 'default' 2>/dev/null

    log "Ext4 loop/jbd2 hiding applied"
}

# ============================================================
# Phase 10: Non-Standard /sdcard Paths Hiding
# ============================================================

apply_sdcard_paths_hiding() {
    log "Applying non-standard /sdcard paths hiding"

    local standard_paths="Alarms Android Audiobooks DCIM Documents Download Movies Music Notifications Pictures Podcasts Ringtones"

    for i in /sdcard/*; do
        [ -e "$i" ] || continue
        local pass=0
        for x in $standard_paths; do
            if [ "/sdcard/${x}" = "$i" ]; then
                pass=1
                break
            fi
        done
        [ "$pass" = "1" ] && continue
        susfs_add_path_loop "$i"
    done

    log "Non-standard /sdcard paths hidden"
}

# ============================================================
# Phase 11: Non-Standard /sdcard/Android Paths Hiding
# ============================================================

apply_sdcard_android_hiding() {
    log "Applying non-standard /sdcard/Android paths hiding"

    local standard_paths="data media obb"

    for i in /sdcard/Android/*; do
        [ -e "$i" ] || continue
        local pass=0
        for x in $standard_paths; do
            if [ "/sdcard/Android/${x}" = "$i" ]; then
                pass=1
                break
            fi
        done
        [ "$pass" = "1" ] && continue
        susfs_add_path_loop "$i"
    done

    log "Non-standard /sdcard/Android paths hidden"
}

# ============================================================
# Phase 12: /sdcard/Android/data Per-App Hiding
# ============================================================

apply_sdcard_android_data_hiding() {
    log "Applying /sdcard/Android/data per-app hiding"

    # Wait for Android/data to be accessible
    local retries=0
    while [ ! -d "/sdcard/Android/data" ] && [ $retries -lt 10 ]; do
        sleep 3
        retries=$((retries + 1))
    done

    for pkg in $(pm list packages -3 2>/dev/null | cut -d':' -f2); do
        if [ -e "/sdcard/Android/data/${pkg}" ]; then
            susfs_add_path "/sdcard/Android/data/${pkg}"
        fi
    done

    log "/sdcard/Android/data per-app hiding applied"
}

# ============================================================
# Phase 13: Module Injection Hiding (all .so in modules/system)
# ============================================================

apply_module_injections_hiding() {
    log "Applying module injection hiding"

    for i in /data/adb/modules/*; do
        if [ -d "${i}/system" ]; then
            find "${i}/system" -type f -name "*.*" 2>/dev/null | while read -r x; do
                susfs_add_map "$x"
            done
        fi
    done

    log "Module injection hiding applied"
}

# ============================================================
# Phase 14: Zygisk Module .so Auto-Scan
# ============================================================

apply_zygisk_auto_scan() {
    log "Applying Zygisk module .so auto-scan"

    find /data/adb/modules -name "*.so" -path "*/zygisk/*" 2>/dev/null | while read -r so_file; do
        susfs_add_map "$so_file"
    done

    log "Zygisk module .so auto-scan applied"
}

# ============================================================
# Phase 15: Recovery/Addon Paths Hiding
# ============================================================

apply_recovery_paths_hiding() {
    log "Applying recovery/addon paths hiding"

    susfs_add_path "/system/addon.d"
    susfs_add_path "/vendor/bin/install-recovery.sh"
    susfs_add_path "/system/bin/install-recovery.sh"
    susfs_add_path "/sdcard/TWRP"
    susfs_add_path "/sdcard/OpenRecovery"
    susfs_add_path "/sdcard/TWRP_backup"

    log "Recovery/addon paths hidden"
}

# ============================================================
# Phase 16: ..5.u.S Leftover Cleanup
# ============================================================

apply_leftover_cleanup() {
    log "Applying ..5.u.S leftover cleanup"

    rm -rf "/sdcard/..5.u.S" 2>/dev/null
    rm -rf "/sdcard/Android/data/..5.u.S" 2>/dev/null
    rm -rf "/sdcard/Android/media/..5.u.S" 2>/dev/null
    rm -rf "/sdcard/Android/obb/..5.u.S" 2>/dev/null

    log "..5.u.S leftover cleanup done"
}

# ============================================================
# Phase 17: inotifyd Watcher (real-time sdcard monitoring)
# ============================================================

start_inotify_watcher() {
    log "Starting inotifyd watcher for /sdcard"

    # Create inotify handler script
    cat > "$PERSISTENT_DIR/inotify_handler.sh" << 'HANDLER'
#!/system/bin/sh
EVENT="$1"
FILE="$2"
# Skip if file doesn't exist
[ -e "$FILE" ] || exit 0
# Skip standard paths
case "$FILE" in
    /sdcard/Alarms*|/sdcard/Android*|/sdcard/Audiobooks*|/sdcard/DCIM*|/sdcard/Documents*|/sdcard/Download*|/sdcard/Movies*|/sdcard/Music*|/sdcard/Notifications*|/sdcard/Pictures*|/sdcard/Podcasts*|/sdcard/Ringtones*)
        exit 0
        ;;
esac
# Hide the new file/directory
/data/adb/ksu/bin/susfs add_sus_path_loop "$FILE" 2>/dev/null
HANDLER
    chmod 755 "$PERSISTENT_DIR/inotify_handler.sh"

    # Kill existing watcher if running
    pkill -f "inotifyd.*inotify_handler" 2>/dev/null

    # Start new watcher
    inotifyd "$PERSISTENT_DIR/inotify_handler.sh" /sdcard:n &
    log "inotifyd watcher started"
}

# ============================================================
# Phase 18: SELinux Enforcement Toggle
# ============================================================

apply_selinux_enforcement() {
    log "Applying SELinux enforcement"

    local current_enforce
    current_enforce=$(getenforce 2>/dev/null)

    if [ "$current_enforce" = "Permissive" ]; then
        setenforce 1 2>/dev/null && \
            log "[selinux]: switched to Enforcing" || \
            log "[selinux FAILED]: could not switch to Enforcing"
    fi
}

# ============================================================
# Main Entry Point
# ============================================================

apply_hiding() {
    local mode="${1:-full}"

    log "Starting SUSFS hiding engine (mode: $mode)"

    # Initialize log
    > "$LOG_FILE" 2>/dev/null

    case "$mode" in
        paths)
            apply_sus_paths
            apply_sus_maps
            ;;
        spoof)
            apply_uname_spoofing
            apply_cmdline_spoofing
            apply_prop_spoofing
            ;;
        mounts)
            apply_mount_hiding
            apply_avc_log_spoofing
            ;;
        lsposed)
            apply_lsposed_hiding
            ;;
        loops)
            apply_ext4_loop_hiding
            ;;
        sdcard)
            apply_sdcard_paths_hiding
            apply_sdcard_android_hiding
            apply_sdcard_android_data_hiding
            ;;
        injections)
            apply_module_injections_hiding
            apply_zygisk_auto_scan
            ;;
        recovery)
            apply_recovery_paths_hiding
            ;;
        cleanup)
            apply_leftover_cleanup
            ;;
        inotify)
            start_inotify_watcher
            ;;
        selinux)
            apply_selinux_enforcement
            ;;
        full)
            apply_sus_paths
            apply_sus_maps
            apply_uname_spoofing
            apply_cmdline_spoofing
            apply_mount_hiding
            apply_avc_log_spoofing
            apply_lsposed_hiding
            apply_ext4_loop_hiding
            apply_prop_spoofing
            apply_sdcard_paths_hiding
            apply_sdcard_android_hiding
            apply_sdcard_android_data_hiding
            apply_module_injections_hiding
            apply_zygisk_auto_scan
            apply_recovery_paths_hiding
            apply_leftover_cleanup
            start_inotify_watcher
            apply_selinux_enforcement
            ;;
        *)
            echo "Usage: $0 {paths|spoof|mounts|lsposed|loops|sdcard|injections|recovery|cleanup|inotify|selinux|full}"
            return 1
            ;;
    esac

    log "SUSFS hiding engine complete"
}

# Run if called directly
if [ "${0##*/}" = "hiding.sh" ] || [ -z "$1" ]; then
    apply_hiding full
fi
