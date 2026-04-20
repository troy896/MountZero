#!/system/bin/sh
# MountZero VFS - ADB Root via Axon Injection
# Injects root capability into adbd using ptrace, matching ZeroMount's approach

AXON_PATH="/data/adb/axon"
INJECT="/data/adb/ksu/bin/axon_inject"
MODDIR="${0%/*}"

log() {
    echo "mountzero-adb: $*" > /dev/kmsg 2>/dev/null
}

# Detect ABI
detect_abIs() {
    if [ -n "$ARCH" ]; then
        case "$ARCH" in
            arm64) echo "arm64-v8a" ;;
            arm)   echo "armeabi-v7a" ;;
            x64)   echo "x86_64" ;;
            x86)   echo "x86" ;;
            *)     echo "" ;;
        esac
    else
        case "$(uname -m)" in
            aarch64)       echo "arm64-v8a" ;;
            armv7*|armv8l) echo "armeabi-v7a" ;;
            x86_64)        echo "x86_64" ;;
            i686|i386)     echo "x86" ;;
            *)             echo "" ;;
        esac
    fi
}

# Stage axon libraries
stage_axon() {
    local abi
    abi=$(detect_abIs)
    [ -z "$abi" ] && { log "Unsupported architecture"; return 1; }

    local init_lib="$MODDIR/lib/${abi}/libaxon_init.so"
    local adbd_lib="$MODDIR/lib/${abi}/libaxon_adbd.so"

    if [ ! -f "$init_lib" ] || [ ! -f "$adbd_lib" ]; then
        log "Axon libraries not found for $abi"
        return 1
    fi

    mkdir -p "$AXON_PATH"
    cp "$init_lib" "$AXON_PATH/"
    cp "$adbd_lib" "$AXON_PATH/"
    chcon -R u:object_r:system_file:s0 "$AXON_PATH"

    log "Axon libraries staged to $AXON_PATH"
    return 0
}

# Patch linker config for ADBD APEX namespace
patch_linker_config() {
    local linker_config="/linkerconfig/com.android.adbd/ld.config.txt"

    if [ ! -f "$linker_config" ]; then
        log "Linker config not found at $linker_config"
        return 1
    fi

    # Check if AXON_PATH is already in permitted paths
    if grep -q "$AXON_PATH" "$linker_config" 2>/dev/null; then
        log "Linker config already patched"
        return 0
    fi

    # Append permitted path
    echo "# mountzero axon" >> "$linker_config"
    echo "namespace.default.permitted.paths += $AXON_PATH" >> "$linker_config"

    log "Linker config patched for $AXON_PATH"
    return 0
}

# Inject axon into init (PID 1)
inject_init() {
    local abi
    abi=$(detect_ABIs)
    [ -z "$abi" ] && return 1

    local injector="$MODDIR/bin/${abi}/axon_inject"
    local init_lib="$AXON_PATH/libaxon_init.so"

    if [ ! -x "$injector" ]; then
        log "Axon injector not found at $injector"
        return 1
    fi

    if [ ! -f "$init_lib" ]; then
        log "Axon init library not found at $init_lib"
        return 1
    fi

    log "Injecting axon into init (PID 1)"
    timeout 5 "$injector" 1 "$init_lib"
    local rc=$?

    if [ $rc -eq 0 ]; then
        log "Axon injection into init successful"
    else
        log "Axon injection into init failed (rc=$rc)"
        return 1
    fi

    return 0
}

# Patch adbd linker config and inject axon into adbd
inject_adbd() {
    local abi
    abi=$(detect_ABIs)
    [ -z "$abi" ] && return 1

    local injector="$MODDIR/bin/${abi}/axon_inject"
    local adbd_lib="$AXON_PATH/libaxon_adbd.so"

    if [ ! -x "$injector" ]; then
        log "Axon injector not found"
        return 1
    fi

    if [ ! -f "$adbd_lib" ]; then
        log "Axon adbd library not found"
        return 1
    fi

    # Find adbd PID
    local adbd_pid
    adbd_pid=$(pgrep -x adbd 2>/dev/null | head -1)
    [ -z "$adbd_pid" ] && { log "adbd process not found"; return 1; }

    log "Injecting axon into adbd (PID $adbd_pid)"
    timeout 5 "$injector" "$adbd_pid" "$adbd_lib"
    local rc=$?

    if [ $rc -eq 0 ]; then
        log "Axon injection into adbd successful"
    else
        log "Axon injection into adbd failed (rc=$rc)"
        return 1
    fi

    return 0
}

# Enable ADB root
enable_adb_root() {
    log "Enabling ADB root via axon injection"

    # Stage libraries
    stage_axon || return 1

    # Patch linker config
    patch_linker_config || return 1

    # Inject into init
    inject_init || return 1

    # Inject into adbd
    inject_adbd || return 1

    log "ADB root enabled successfully"
    return 0
}

# Disable ADB root
disable_adb_root() {
    log "Disabling ADB root"

    # Remove axon libraries
    rm -rf "$AXON_PATH" 2>/dev/null

    # Restore linker config
    local linker_config="/linkerconfig/com.android.adbd/ld.config.txt"
    if [ -f "$linker_config" ]; then
        sed -i '/mountzero axon/d' "$linker_config" 2>/dev/null
        sed -i '/axon/d' "$linker_config" 2>/dev/null
    fi

    log "ADB root disabled"
    return 0
}

# Main
case "$1" in
    enable)
        enable_adb_root
        ;;
    disable)
        disable_adb_root
        ;;
    status)
        if [ -d "$AXON_PATH" ] && [ -f "$AXON_PATH/libaxon_adbd.so" ]; then
            echo "ADB root: ENABLED"
        else
            echo "ADB root: DISABLED"
        fi
        ;;
    *)
        echo "Usage: $0 {enable|disable|status}"
        exit 1
        ;;
esac
