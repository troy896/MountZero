#!/system/bin/sh
# MountZero VFS - KSU/APatch Metamodule Mount Hook
# Full mount pipeline: overlay mounts for modules + VFS redirects
# Equivalent to ZeroMount's metamount.sh + Rust binary mount engine

MODDIR="${0%/*}"
LOG="mountzero"
CONFIG_DIR="/data/adb/mountzero"
CONFIG_FILE="$CONFIG_DIR/config.toml"
MZCTL="/data/adb/ksu/bin/mzctl"
CONFIG_SH="$MODDIR/config.sh"
BRIDGE_SH="$MODDIR/bridge.sh"
HIDING_SH="$MODDIR/hiding.sh"

WORK_BASE="/dev/mountzero_work"
UPPER_BASE="/dev/mountzero_upper"

# Single-instance lock
LOCKFILE="/dev/mountzero_metamount_lock"
( set -o noclobber; > "$LOCKFILE" ) 2>/dev/null || {
    $MZCTL enable 2>/dev/null
    /data/adb/ksud kernel notify-module-mounted 2>/dev/null
    exit 0
}

echo "$LOG: metamount.sh entered (post-fs-data)" > /dev/kmsg 2>/dev/null

# Bootloop guard
COUNT=$(cat "$CONFIG_DIR/.bootcount" 2>/dev/null || echo 0)
if [ "$COUNT" -ge 3 ]; then
    echo "$LOG: bootloop guard tripped (count=$COUNT), skipping pipeline" > /dev/kmsg 2>/dev/null
    $MZCTL enable 2>/dev/null
    /data/adb/ksud kernel notify-module-mounted 2>/dev/null
    exit 0
fi

# Detect architecture
if [ -n "$ARCH" ]; then
    case "$ARCH" in
        arm64) ABI=arm64-v8a ;;
        arm)   ABI=armeabi-v7a ;;
        x64)   ABI=x86_64 ;;
        x86)   ABI=x86 ;;
        *)     ABI="" ;;
    esac
else
    case "$(uname -m)" in
        aarch64)       ABI=arm64-v8a ;;
        armv7*|armv8l) ABI=armeabi-v7a ;;
        x86_64)        ABI=x86_64 ;;
        i686|i386)     ABI=x86 ;;
        *)             ABI="" ;;
    esac
fi

# ============================================================
# Overlay Mount Engine
# ============================================================

# Clean up stale overlay mounts from failed boots
cleanup_stale_mounts() {
    echo "$LOG: cleaning up stale overlay mounts" > /dev/kmsg 2>/dev/null
    # Unmount any leftover mountzero overlay mounts
    grep "mountzero_work\|mountzero_upper" /proc/mounts 2>/dev/null | while read -r line; do
        local mp
        mp=$(echo "$line" | awk '{print $2}')
        if echo "$mp" | grep -q "^/system\|^/vendor\|^/product\|^/system_ext\|^/odm"; then
            umount -l "$mp" 2>/dev/null
        fi
    done

    # Clean work/upper dirs
    rm -rf "$WORK_BASE" 2>/dev/null
    rm -rf "$UPPER_BASE" 2>/dev/null
    mkdir -p "$WORK_BASE"
    mkdir -p "$UPPER_BASE"
}

# Mount a single partition via overlayfs
# Args: module_id, partition, module_path
mount_partition_overlay() {
    local modid="$1"
    local partition="$2"
    local modpath="$3"
    local source_dir="$modpath/$partition"

    # Skip if partition directory doesn't exist in module
    [ -d "$source_dir" ] || return 0

    # Check if target exists on device
    local target_dir="/$partition"
    [ -d "$target_dir" ] || return 0

    # Create work and upper directories
    local work_dir="$WORK_BASE/${modid}_${partition}_work"
    local upper_dir="$UPPER_BASE/${modid}_${partition}_upper"
    mkdir -p "$work_dir" 2>/dev/null
    mkdir -p "$upper_dir" 2>/dev/null

    # Set correct SELinux context on upper/work dirs
    chcon u:object_r:system_file:s0 "$upper_dir" 2>/dev/null
    chcon u:object_r:system_file:s0 "$work_dir" 2>/dev/null

    # Mount overlay
    mount -t overlay "mountzero_${modid}_${partition}" \
        -o "lowerdir=$source_dir:$target_dir,upperdir=$upper_dir,workdir=$work_dir" \
        "$target_dir" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "$LOG: overlay mounted: $modid/$partition → /$partition" > /dev/kmsg 2>/dev/null
        return 0
    else
        echo "$LOG: overlay failed: $modid/$partition (falling back to VFS)" > /dev/kmsg 2>/dev/null
        return 1
    fi
}

# Unmount a module's overlay partitions
unmount_module_overlays() {
    local modid="$1"

    grep "mountzero_${modid}_" /proc/mounts 2>/dev/null | while read -r line; do
        local mp
        mp=$(echo "$line" | awk '{print $2}')
        umount -l "$mp" 2>/dev/null
        echo "$LOG: unmounted overlay: $mp ($modid)" > /dev/kmsg 2>/dev/null
    done
}

# ============================================================
# Main Mount Pipeline
# ============================================================

if [ -n "$ABI" ] && [ -x "$MZCTL" ]; then
    # Step 1: Clean up stale mounts
    cleanup_stale_mounts

    # Step 2: Run other modules' post-fs-data scripts BEFORE mount pipeline
    echo "$LOG: running other modules' post-fs-data scripts (pre-mount)" > /dev/kmsg 2>/dev/null
    for _pfd in /data/adb/modules/*/post-fs-data.sh; do
        [ ! -f "$_pfd" ] && continue
        _pfd_dir="${_pfd%/post-fs-data.sh}"
        _pfd_mod="${_pfd_dir##*/}"
        case "$_pfd_mod" in
            mountzero_vfs|meta-mountzero_vfs) continue ;;
        esac
        [ -f "${_pfd_dir}/disable" ] && continue
        [ -f "${_pfd_dir}/remove" ] && continue
        echo "$LOG: pre-mount: executing $_pfd_mod/post-fs-data.sh" > /dev/kmsg 2>/dev/null
        (cd "$_pfd_dir" && timeout 30 sh post-fs-data.sh) 2>/dev/null
        echo "$LOG: pre-mount: $_pfd_mod exited (rc=$?)" > /dev/kmsg 2>/dev/null
    done

    # Step 3: Enable MountZero VFS engine
    echo "$LOG: enabling MountZero VFS" > /dev/kmsg 2>/dev/null
    "$MZCTL" enable 2>/dev/null

    # Step 4: Reconcile external SUSFS configs
    if [ -x "$BRIDGE_SH" ]; then
        echo "$LOG: reconciling external SUSFS configs" > /dev/kmsg 2>/dev/null
        "$BRIDGE_SH" reconcile all 2>/dev/null
        "$BRIDGE_SH" write "$CONFIG_FILE" 2>/dev/null
    fi

    # Step 5: Scan modules and mount via overlay + VFS
    echo "$LOG: starting module mount pipeline (pre-zygote)" > /dev/kmsg 2>/dev/null

    PARTITIONS="system vendor product system_ext odm odm_dlkm vendor_dlkm"

    for moddir in /data/adb/modules/*/; do
        [ -d "$moddir" ] || continue
        modid=$(basename "$moddir")

        # Skip ourselves and disabled modules
        case "$modid" in
            mountzero_vfs|meta-mountzero_vfs) continue ;;
        esac
        [ -f "${moddir}disable" ] && continue
        [ -f "${moddir}remove" ] && continue
        [ -f "${moddir}skip_mount" ] && continue

        echo "$LOG: mounting module: $modid" > /dev/kmsg 2>/dev/null

        # Try overlay mounts for each partition
        overlay_success=0
        for part in $PARTITIONS; do
            if [ -d "${moddir}${part}" ]; then
                if mount_partition_overlay "$modid" "$part" "$moddir"; then
                    overlay_success=$((overlay_success + 1))
                fi
            fi
        done

        if [ $overlay_success -eq 0 ]; then
            # Fallback to VFS path redirection
            echo "$LOG: overlay not available, using VFS redirect for: $modid" > /dev/kmsg 2>/dev/null
            "$MZCTL" module install "$modid" "$moddir" 2>/dev/null
        else
            echo "$LOG: overlay mounted: $overlay_success partitions for: $modid" > /dev/kmsg 2>/dev/null
        fi
    done

    # Step 6: Scan custom modules in /data/local/
    for moddir in /data/local/*/; do
        [ -d "$moddir" ] || continue
        modid=$(basename "$moddir")
        case "$modid" in
            lost+found|tmp|media|oem|vendor|system|tests|traces) continue ;;
        esac
        echo "$LOG: mounting custom module: $modid" > /dev/kmsg 2>/dev/null
        # Custom modules use VFS redirect (maps /data/local/X → /system)
        "$MZCTL" module install "$modid" "$moddir" custom 2>/dev/null
    done

    # Step 7: Create self-bind mounts for /data/local/ modules (for /proc/mounts visibility)
    for moddir in /data/local/*/; do
        [ -d "$moddir" ] || continue
        modid=$(basename "$moddir")
        case "$modid" in
            lost+found|tmp|media|oem|vendor|system) continue ;;
        esac
        mount --bind "$moddir" "$moddir" 2>/dev/null
    done

    echo "$LOG: module mount pipeline complete" > /dev/kmsg 2>/dev/null

    # Step 8: Apply SUSFS hiding (BRENE integration)
    if [ -x "$HIDING_SH" ]; then
        echo "$LOG: applying SUSFS hiding engine" > /dev/kmsg 2>/dev/null
        . "$HIDING_SH"
        apply_hiding full
        echo "$LOG: SUSFS hiding engine complete" > /dev/kmsg 2>/dev/null
    fi

else
    echo "$LOG: mzctl not found (ABI=$ABI), skipping pipeline" > /dev/kmsg 2>/dev/null
fi

# ============================================================
# ADB Root
# ============================================================

if [ -f "$CONFIG_FILE" ]; then
    ADB_ROOT_ENABLED=$("$CONFIG_SH" get adb adbRoot false 2>/dev/null)
    if [ "$ADB_ROOT_ENABLED" = "true" ] && [ -x "$MODDIR/axon.sh" ]; then
        echo "$LOG: enabling ADB root via axon injection" > /dev/kmsg 2>/dev/null
        "$MODDIR/axon.sh" enable 2>/dev/null
    fi
fi

# ============================================================
# Notify KSU that mounts are ready (triggers Zygote)
# ============================================================

echo "$LOG: calling notify-module-mounted" > /dev/kmsg 2>/dev/null
/data/adb/ksud kernel notify-module-mounted 2>/dev/null
exit 0
