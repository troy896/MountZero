#!/system/bin/sh
# MountZero VFS - Config Manager
# Handles config.toml read/write, defaults, and validation

CONFIG_DIR="/data/adb/mountzero"
CONFIG_FILE="$CONFIG_DIR/config.toml"

init_config() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR/logs"

    if [ -f "$CONFIG_FILE" ]; then
        return 0
    fi

    cat > "$CONFIG_FILE" << 'TOML'
# MountZero VFS Configuration
# Generated automatically on first boot

[mount]
mountEngine = "vfs"          # vfs, overlay, magic
mountSource = "KSU"          # KSU, APatch, Magisk
overlayPreferred = false
ext4ImageSizeMB = 512
randomMountPaths = true
excludeHostsModules = []

[partitions]
extra = ["product", "system_ext", "vendor"]

[susfs]
enabled = true
pathHide = true
mapsHide = true
kstat = true
susfsLog = false
avcLogSpoofing = true
hiddenPaths = []
hiddenMaps = []

[brene]
verifiedBootHash = ""
kernelUmount = false
tryUmount = false
emulateVoldAppData = false
autoHideApk = false
autoHideFonts = false
autoHideRootedFolders = false
hideSusMounts = false
forceHideLsposed = false
spoofCmdline = false
hideKsuLoops = false
propSpoofing = false
autoHideInjections = false
toggle = false
hideAndroidData = false
hideModuleInjections = false
zygiskAutoScan = false
hideRecovery = false
cleanupLeftovers = false
inotifyWatcher = false
selinuxEnforce = false

[guard]
enabled = true
bootTimeout = 120
markerThreshold = 3
zygoteWatchSecs = 30
systemuiAbsentTimeout = 30
protectedModules = ["rezygisk", "zygisk_lsposed"]

[perf]
enabled = true
boostKhz = 0
schedMigrationCostNs = 500000
schedMinGranularityNs = 3000000
schedWakeupGranularityNs = 500000
schedChildRunsFirst = true

[adb]
adbRoot = false
developerOptions = false
usbDebugging = false
TOML

    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
}

# Simple TOML value getter (no nested support, flat keys only)
config_get() {
    local section="$1"
    local key="$2"
    local default="${3:-}"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "$default"
        return
    fi

    local in_section=0
    local value=""

    while IFS= read -r line; do
        # Check for section header
        case "$line" in
            \[$section\])
                in_section=1
                continue
                ;;
            \[*\])
                if [ $in_section -eq 1 ]; then
                    in_section=0
                fi
                continue
                ;;
        esac

        if [ $in_section -eq 1 ]; then
            # Strip comments and whitespace
            line=$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            [ -z "$line" ] && continue

            # Match key = value
            local k v
            k=$(echo "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')
            v=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//')

            if [ "$k" = "$key" ]; then
                # Strip quotes from string values
                value=$(echo "$v" | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//")
                echo "$value"
                return
            fi
        fi
    done < "$CONFIG_FILE"

    echo "$default"
}

# Simple TOML value setter (creates key if missing)
config_set() {
    local section="$1"
    local key="$2"
    local value="$3"

    if [ ! -f "$CONFIG_FILE" ]; then
        init_config
    fi

    # Check if key exists
    local current
    current=$(config_get "$section" "$key")

    if [ -n "$current" ] || grep -q "^\[$section\]" "$CONFIG_FILE"; then
        # Update existing key
        local tmp_file="$CONFIG_FILE.tmp"
        local in_section=0
        local found=0

        > "$tmp_file"

        while IFS= read -r line; do
            case "$line" in
                \[$section\])
                    in_section=1
                    echo "$line" >> "$tmp_file"
                    continue
                    ;;
                \[*\])
                    if [ $in_section -eq 1 ]; then
                        in_section=0
                    fi
                    ;;
            esac

            if [ $in_section -eq 1 ] && [ $found -eq 0 ]; then
                local k
                k=$(echo "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')
                if [ "$k" = "$key" ]; then
                    echo "$key = $value" >> "$tmp_file"
                    found=1
                    continue
                fi
            fi

            echo "$line" >> "$tmp_file"
        done < "$CONFIG_FILE"

        # If key wasn't found, append to section
        if [ $found -eq 0 ]; then
            # Find section and append key after it
            local before after
            before=$(sed -n "1,/\[$section\]/p" "$CONFIG_FILE")
            after=$(sed "1,/\[$section\]/d" "$CONFIG_FILE")
            echo "$before" > "$tmp_file"
            echo "$key = $value" >> "$tmp_file"
            echo "$after" >> "$tmp_file"
        fi

        mv "$tmp_file" "$CONFIG_FILE"
    else
        # Add new section and key
        echo "" >> "$CONFIG_FILE"
        echo "[$section]" >> "$CONFIG_FILE"
        echo "$key = $value" >> "$CONFIG_FILE"
    fi

    chmod 600 "$CONFIG_FILE"
}

# Detect mount source
detect_mount_source() {
    if [ -n "$KSU" ] && [ "$KSU" = true ]; then
        echo "KSU"
    elif [ -n "$APATCH" ] && [ "$APATCH" = true ]; then
        echo "APatch"
    elif [ -d "/data/adb/magisk" ]; then
        echo "Magisk"
    else
        echo "Unknown"
    fi
}

# Sync device properties to config
sync_device_props() {
    local dev_lang=$(getprop ro.system.locale 2>/dev/null || getprop persist.sys.locale 2>/dev/null || getprop ro.product.locale 2>/dev/null || echo "en")
    config_set "ui" "language" "$dev_lang"

    local dev_brand=$(getprop ro.product.brand 2>/dev/null | tr '[:upper:]' '[:lower:]')
    config_set "device" "brand" "$dev_brand"

    local vbmeta_size=$(( 4096 + ($(od -An -tu1 -N1 /dev/urandom 2>/dev/null || echo 0) % 8) * 1024 ))
    config_set "brene" "vbmeta_size" "$vbmeta_size"
}

# Main
case "$1" in
    init)
        init_config
        sync_device_props
        echo "Config initialized"
        ;;
    get)
        config_get "$2" "$3" "${4:-}"
        ;;
    set)
        config_set "$2" "$3" "$4"
        echo "Config set: $2.$3 = $4"
        ;;
    dump)
        if [ -f "$CONFIG_FILE" ]; then
            cat "$CONFIG_FILE"
        else
            echo "Config file not found"
            exit 1
        fi
        ;;
    source)
        detect_mount_source
        ;;
    *)
        echo "Usage: $0 {init|get|set|dump|source} [args...]"
        exit 1
        ;;
esac
