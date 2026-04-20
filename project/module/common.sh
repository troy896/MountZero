#!/system/bin/sh
# MountZero VFS - Shared utilities

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

if [ -n "$MODDIR" ] && [ -n "$ABI" ]; then
    MZCTL="$MODDIR/bin/mzctl"
    KSU_MZCTL="/data/adb/ksu/bin/mzctl"
fi
