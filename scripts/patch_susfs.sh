#!/bin/bash
# SUSFS v2.1.0 Kernel Patcher
# Applies SUSFS v2.1.0 core patches to a kernel source tree
#
# Usage: ./patch_susfs.sh /path/to/kernel/source
#
# This script applies SUSFS v2.1.0 patches for your kernel version.
# MountZero VFS requires SUSFS v2.1.0 to be applied first.
#
# Supported kernel versions: 4.14, 5.15
#
# License: GPL v2.0
# Author: Enginex0 (SUSFS) / Integrated by 爪卂丂ㄒ乇尺爪工刀ᗪ丂

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${1:-}"
PATCH_DIR="$SCRIPT_DIR/../kernel/patches/susfs-v2.1.0"

if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: $0 /path/to/kernel/source"
    echo ""
    echo "Example: $0 ~/android_kernel_samsung_mt6768"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Kernel source directory not found: $SOURCE_DIR"
    exit 1
fi

if [ ! -f "$SOURCE_DIR/Makefile" ]; then
    echo "Error: No valid kernel source found at $SOURCE_DIR"
    echo "Expected: Makefile at root of kernel source"
    exit 1
fi

echo "============================================="
echo "  SUSFS v2.1.0 Kernel Patcher"
echo "============================================="
echo ""
echo "Target: $SOURCE_DIR"
echo "Patches: $PATCH_DIR"
echo ""

# Detect kernel version
KVERSION=""
if grep -q "VERSION.*=.*4" "$SOURCE_DIR/Makefile" 2>/dev/null && \
   grep -q "PATCHLEVEL.*=.*14" "$SOURCE_DIR/Makefile" 2>/dev/null; then
    KVERSION="4.14"
elif grep -q "VERSION.*=.*5" "$SOURCE_DIR/Makefile" 2>/dev/null && \
     grep -q "PATCHLEVEL.*=.*15" "$SOURCE_DIR/Makefile" 2>/dev/null; then
    KVERSION="5.15"
else
    # Try to detect from version string
    VSTRING=$(grep "^VERSION" "$SOURCE_DIR/Makefile" 2>/dev/null | head -1)
    PSTRING=$(grep "^PATCHLEVEL" "$SOURCE_DIR/Makefile" 2>/dev/null | head -1)
    if echo "$VSTRING $PSTRING" | grep -q "4.*14"; then
        KVERSION="4.14"
    elif echo "$VSTRING $PSTRING" | grep -q "5.*15"; then
        KVERSION="5.15"
    fi
fi

if [ -z "$KVERSION" ]; then
    echo "⚠️  Could not auto-detect kernel version"
    echo ""
    echo "Available SUSFS patches:"
    ls -1 "$PATCH_DIR" 2>/dev/null | sed 's/^/  /'
    echo ""
    echo "Please run the appropriate patch manually:"
    echo "  cd $SOURCE_DIR"
    echo "  patch -p1 < $PATCH_DIR/<patch-file>"
    exit 1
fi

echo "Detected kernel version: $KVERSION"
echo ""

# Find the matching patch
PATCH_FILE=""
for f in "$PATCH_DIR"/*susfs*"$KVERSION"*; do
    if [ -f "$f" ]; then
        PATCH_FILE="$f"
        break
    fi
done

if [ -z "$PATCH_FILE" ]; then
    echo "❌ No SUSFS v2.1.0 patch found for kernel $KVERSION"
    echo ""
    echo "Available patches:"
    ls -1 "$PATCH_DIR" 2>/dev/null | sed 's/^/  /'
    exit 1
fi

echo "Applying: $(basename "$PATCH_FILE")"
echo ""

cd "$SOURCE_DIR"

# Dry run first
if patch -p1 --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
    patch -p1 < "$PATCH_FILE"
    echo ""
    echo "✅ SUSFS v2.1.0 patches applied successfully!"
else
    echo "⚠️  Patch failed dry-run, applying with fuzz..."
    patch -p1 --fuzz=3 < "$PATCH_FILE" || {
        echo "❌ Patch application failed"
        exit 1
    }
    echo ""
    echo "⚠️  SUSFS v2.1.0 patches applied (some hunks may have been skipped)"
fi

echo ""
echo "============================================="
echo "  ✅ SUSFS v2.1.0 Patching Complete!"
echo "============================================="
echo ""
echo "Next step: Apply MountZero VFS patches"
echo "  $SCRIPT_DIR/patch_kernel.sh $SOURCE_DIR"
echo ""
