#!/system/bin/sh
# MountZero VFS - Metamodule Install Hook
# Called by KSU when ANOTHER module is installed.
# Handles hot-install with overlay mount.

MODDIR="${0%/*}"
MZCTL="/data/adb/ksu/bin/mzctl"
CONFIG_DIR="/data/adb/mountzero"
WORK_BASE="/dev/mountzero_work"
UPPER_BASE="/dev/mountzero_upper"

KSU_HAS_METAMODULE=true
KSU_METAMODULE=mountzero_vfs
export KSU_HAS_METAMODULE KSU_METAMODULE

# Stub to suppress default partition handling
handle_partition() { : ; }

install_module

# Fix SELinux context on system/ dirs
if [ -d "$MODPATH/system" ] && command -v chcon >/dev/null 2>&1; then
    chcon -R u:object_r:system_file:s0 "$MODPATH/system" 2>/dev/null
fi

# Hot-mount the newly installed module with overlay
hot_mount_module() {
    local modid="$MODID"
    local moddir="/data/adb/modules/$modid"

    [ -d "$moddir" ] || return 0
    [ -f "${moddir}disable" ] && return 0
    [ -f "${moddir}remove" ] && return 0

    echo "mountzero: hot-mounting module: $modid" > /dev/kmsg 2>/dev/null

    # Mount overlay for each partition
    local PARTITIONS="system vendor product system_ext odm"
    local mounted=0

    for part in $PARTITIONS; do
        if [ -d "${moddir}${part}" ]; then
            mkdir -p "${WORK_BASE}/${modid}_${part}_work" 2>/dev/null
            mkdir -p "${UPPER_BASE}/${modid}_${part}_upper" 2>/dev/null

            mount -t overlay "mountzero_${modid}_${part}" \
                -o "lowerdir=${moddir}${part}:/${part},upperdir=${UPPER_BASE}/${modid}_${part}_upper,workdir=${WORK_BASE}/${modid}_${part}_work" \
                "/${part}" 2>/dev/null

            if [ $? -eq 0 ]; then
                mounted=$((mounted + 1))
            else
                # Fallback to VFS
                $MZCTL module install "$modid" "$moddir" 2>/dev/null
            fi
        fi
    done

    if [ $mounted -gt 0 ]; then
        echo "mountzero: hot-mounted $mounted partitions for: $modid" > /dev/kmsg 2>/dev/null
    fi
}

# Run hot-mount after install
hot_mount_module

# Hot-install support for KSU
metamodule_hot_install() {
    [ "$KSU" = true ] || return
    [ -n "$MODID" ] || return

    MODDIR_LIVE="/data/adb/modules/$MODID"
    MODPATH_STAGED="/data/adb/modules_update/$MODID"
    [ -d "$MODDIR_LIVE" ] && [ -d "$MODPATH_STAGED" ] || return

    # Unmount old overlays if module exists
    grep "mountzero_${MODID}_" /proc/mounts 2>/dev/null | while read -r line; do
        local mp
        mp=$(echo "$line" | awk '{print $2}')
        umount -l "$mp" 2>/dev/null
    done

    busybox rm -rf "$MODDIR_LIVE"
    busybox mv "$MODPATH_STAGED" "$MODDIR_LIVE"

    if [ -n "$MODULE_HOT_RUN_SCRIPT" ] && [ -f "$MODDIR_LIVE/$MODULE_HOT_RUN_SCRIPT" ]; then
        sh "$MODDIR_LIVE/$MODULE_HOT_RUN_SCRIPT"
    fi

    # stub satisfies KSU's ensure_file_exists check
    mkdir -p "$MODPATH_STAGED"
    cat "$MODDIR_LIVE/module.prop" > "$MODPATH_STAGED/module.prop"

    # Hot-mount the updated module
    hot_mount_module

    ( sleep 3; rm -rf "$MODDIR_LIVE/update" "$MODPATH_STAGED" ) &

    ui_print "- Module hot-installed, no reboot needed!"
    ui_print "- Refresh module list to see changes."
}

[ "$MODULE_HOT_INSTALL_REQUEST" = true ] && metamodule_hot_install
