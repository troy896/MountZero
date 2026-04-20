#!/system/bin/sh
# MountZero VFS - SUSFS Bridge
# Reconciles external SUSFS module configs (susfs4ksu, brene) bidirectionally

MZ_DATA="/data/adb/mountzero"
MZ_CONFIG="$MZ_DATA/config.toml"
SUSFS4KSU_CONFIG="/data/adb/susfs4ksu/config.toml"
BRENE_CONFIG="/data/adb/brene/config.toml"

log() {
    echo "mountzero-bridge: $*" > /dev/kmsg 2>/dev/null
}

# Reconcile SUSFS config from external modules
bridge_reconcile() {
    local target="$1"
    local changes=0

    case "$target" in
        susfs4ksu)
            if [ ! -f "$SUSFS4KSU_CONFIG" ]; then
                log "susfs4ksu config not found at $SUSFS4KSU_CONFIG"
                return 1
            fi

            log "Reconciling susfs4ksu config"

            # Import SUSFS path hiding rules
            if grep -q 'path_hide.*=.*true' "$SUSFS4KSU_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set susfs.path_hide true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import SUSFS maps hiding rules
            if grep -q 'maps_hide.*=.*true' "$SUSFS4KSU_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set susfs.maps_hide true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import kstat spoofing
            if grep -q 'kstat.*=.*true' "$SUSFS4KSU_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set susfs.kstat true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import SUSFS log setting
            if grep -q 'susfs_log.*=.*true' "$SUSFS4KSU_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set susfs.susfs_log true 2>/dev/null
                changes=$((changes + 1))
            fi

            log "Reconciled $changes susfs4ksu settings"
            ;;

        brene)
            if [ ! -f "$BRENE_CONFIG" ]; then
                log "brene config not found at $BRENE_CONFIG"
                return 1
            fi

            log "Reconciling brene config"

            # Import BRENE verified boot hash
            local vbh
            vbh=$(grep 'verifiedBootHash' "$BRENE_CONFIG" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
            if [ -n "$vbh" ]; then
                /data/adb/ksu/bin/mzctl config set brene.verified_boot_hash "$vbh" 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import BRENE kernel umount setting
            if grep -q 'kernelUmount.*=.*true' "$BRENE_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set brene.kernel_umount true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import BRENE try_umount setting
            if grep -q 'tryUmount.*=.*true' "$BRENE_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set brene.try_umount true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import BRENE hide SUSFS mounts
            if grep -q 'hideSusMounts.*=.*true' "$BRENE_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set brene.hide_sus_mounts true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import BRENE LSPosed hiding
            if grep -q 'forceHideLsposed.*=.*true' "$BRENE_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set brene.force_hide_lsposed true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import BRENE cmdline spoofing
            if grep -q 'spoofCmdline.*=.*true' "$BRENE_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set brene.spoof_cmdline true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import BRENE KSU loop hiding
            if grep -q 'hideKsuLoops.*=.*true' "$BRENE_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set brene.hide_ksu_loops true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import BRENE prop spoofing
            if grep -q 'propSpoofing.*=.*true' "$BRENE_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set brene.prop_spoofing true 2>/dev/null
                changes=$((changes + 1))
            fi

            # Import BRENE auto-hide injections
            if grep -q 'autoHideInjections.*=.*true' "$BRENE_CONFIG" 2>/dev/null; then
                /data/adb/ksu/bin/mzctl config set brene.auto_hide_injections true 2>/dev/null
                changes=$((changes + 1))
            fi

            log "Reconciled $changes brene settings"
            ;;

        all)
            bridge_reconcile susfs4ksu
            bridge_reconcile brene
            ;;

        *)
            echo "Usage: $0 {susfs4ksu|brene|all}"
            return 1
            ;;
    esac

    return 0
}

# Write SUSFS rules from MountZero config to kernel
bridge_write_susfs() {
    local config_file="$1"
    [ -z "$config_file" ] && config_file="$MZ_CONFIG"
    [ -f "$config_file" ] || { echo "Config not found: $config_file"; return 1; }

    local mzctl="/data/adb/ksu/bin/mzctl"
    local count=0

    # Apply SUSFS path hiding
    local path_hide
    path_hide=$("$MZ_DATA/config.sh" get susfs path_hide true 2>/dev/null)
    if [ "$path_hide" = "true" ]; then
        # Read hidden paths from config and add them
        while IFS= read -r path; do
            [ -z "$path" ] && continue
            path=$(echo "$path" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            [ -z "$path" ] && continue
            $mzctl susfs add-path "$path" 2>/dev/null
            count=$((count + 1))
        done < <(grep -A100 '^\[susfs\]' "$config_file" | grep -B100 '^\[' | grep 'hiddenPaths' | tr ',' '\n' | sed 's/.*"//' | sed 's/".*//')
    fi

    # Apply SUSFS maps hiding
    local maps_hide
    maps_hide=$("$MZ_DATA/config.sh" get susfs maps_hide true 2>/dev/null)
    if [ "$maps_hide" = "true" ]; then
        while IFS= read -r map; do
            [ -z "$map" ] && continue
            map=$(echo "$map" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            [ -z "$map" ] && continue
            $mzctl susfs add-map "$map" 2>/dev/null
            count=$((count + 1))
        done < <(grep -A100 '^\[susfs\]' "$config_file" | grep -B100 '^\[' | grep 'hiddenMaps' | tr ',' '\n' | sed 's/.*"//' | sed 's/".*//')
    fi

    # Apply kstat spoofing
    local kstat
    kstat=$("$MZ_DATA/config.sh" get susfs kstat true 2>/dev/null)
    if [ "$kstat" = "true" ]; then
        $mzctl susfs kstat enable 2>/dev/null
        count=$((count + 1))
    fi

    # Apply SUSFS log
    local susfs_log
    susfs_log=$("$MZ_DATA/config.sh" get susfs susfs_log false 2>/dev/null)
    if [ "$susfs_log" = "true" ]; then
        $mzctl susfs log enable 2>/dev/null
        count=$((count + 1))
    fi

    # Apply AVC log spoofing
    local avc_log
    avc_log=$("$MZ_DATA/config.sh" get susfs avcLogSpoofing false 2>/dev/null)
    if [ "$avc_log" = "true" ]; then
        $mzctl susfs avc enable 2>/dev/null
        count=$((count + 1))
    fi

    # Apply uname spoofing
    local uname_release uname_version
    uname_release=$("$MZ_DATA/config.sh" get susfs uname_release "" 2>/dev/null)
    uname_version=$("$MZ_DATA/config.sh" get susfs uname_version "" 2>/dev/null)
    if [ -n "$uname_release" ] && [ -n "$uname_version" ]; then
        $mzctl susfs set-uname "$uname_release" "$uname_version" 2>/dev/null
        count=$((count + 1))
    fi

    # Apply cmdline spoofing
    local spoof_cmdline
    spoof_cmdline=$("$MZ_DATA/config.sh" get brene spoof_cmdline true 2>/dev/null)
    if [ "$spoof_cmdline" = "true" ]; then
        local cmdline_file="$MZ_DATA/fake_cmdline.txt"
        if [ -f "$cmdline_file" ]; then
            $mzctl susfs set-cmdline "$cmdline_file" 2>/dev/null
            count=$((count + 1))
        fi
    fi

    # Apply hide SUSFS mounts
    local hide_mounts
    hide_mounts=$("$MZ_DATA/config.sh" get brene hide_sus_mounts true 2>/dev/null)
    if [ "$hide_mounts" = "true" ]; then
        /data/adb/ksu/bin/ksu_susfs hide_sus_mnts_for_non_su_procs 1 2>/dev/null
        count=$((count + 1))
    fi

    echo "SUSFS bridge applied: $count rules"
    return 0
}

# Main
case "$1" in
    reconcile)
        bridge_reconcile "$2"
        ;;
    write)
        bridge_write_susfs "$2"
        ;;
    init)
        bridge_reconcile all
        bridge_write_susfs "$2"
        ;;
    *)
        echo "Usage: $0 {reconcile|write|init} [target]"
        exit 1
        ;;
esac
