#!/bin/bash
#
# MountZero Integration Script
# Run from your kernel source root directory
# Usage: ./project/integrate.sh
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="$(pwd)"
MZ_KERNEL="$SCRIPT_DIR/kernel"

echo "========================================"
echo "  MountZero VFS Integration"
echo "========================================"

# Check running from kernel source
if [ ! -d "$KERNEL_DIR/fs" ]; then
    echo "❌ Run this from YOUR KERNEL SOURCE ROOT!"
    echo "   Not from the MountZero project folder."
    exit 1
fi

# Check MountZero files exist
if [ ! -f "$MZ_KERNEL/mountzero.c" ]; then
    echo "❌ MountZero kernel files not found!"
    echo "   Expected: $MZ_KERNEL/mountzero.c"
    exit 1
fi

echo ""
echo "Checking kernel configuration..."

# Check for SUSFS (required!)
if [ -f "$KERNEL_DIR/include/linux/susfs_def.h" ] || \
   grep -q "CONFIG_KSU_SUSFS" "$KERNEL_DIR"/*/defconfig 2>/dev/null || \
   grep -q "CONFIG_KSU_SUSFS" "$KERNEL_DIR"/arch/*/configs/* 2>/dev/null; then
    echo "  ✅ SUSFS found in kernel"
else
    echo "  ⚠️  WARNING: SUSFS not detected in kernel config"
    echo "           MountZero requires CONFIG_KSU_SUSFS=y"
    echo "           Build may fail if SUSFS is not integrated."
fi

echo ""
echo "📁 Copying kernel files..."

# Copy source files
cp -v "$MZ_KERNEL/mountzero.c" "$KERNEL_DIR/fs/"
cp -v "$MZ_KERNEL/mountzero_vfs.c" "$KERNEL_DIR/fs/"
echo "  ✅ fs/mountzero.c"

# Copy header files
cp -v "$MZ_KERNEL/"mountzero*.h "$KERNEL_DIR/include/linux/"
echo "  ✅ include/linux/mountzero*.h"

# Add to Makefile
if ! grep -q "mountzero.o" "$KERNEL_DIR/fs/Makefile" 2>/dev/null; then
    echo "" >> "$KERNEL_DIR/fs/Makefile"
    echo "obj-y += mountzero.o mountzero_vfs.o" >> "$KERNEL_DIR/fs/Makefile"
    echo "  ✅ Added to fs/Makefile"
else
    echo "  ⏭️  Already in fs/Makefile"
fi

# Add to Kconfig if exists
if [ -f "$KERNEL_DIR/fs/Kconfig" ]; then
    if ! grep -q "config MOUNTZERO" "$KERNEL_DIR/fs/Kconfig" 2>/dev/null; then
        echo "" >> "$KERNEL_DIR/fs/Kconfig"
        echo "config MOUNTZERO" >> "$KERNEL_DIR/fs/Kconfig"
        echo "    bool \"MountZero VFS\"" >> "$KERNEL_DIR/fs/Kconfig"
        echo "    depends on KSU_SUSFS" >> "$KERNEL_DIR/fs/Kconfig"
        echo "    default y" >> "$KERNEL_DIR/fs/Kconfig"
        echo "    help" >> "$KERNEL_DIR/fs/Kconfig"
        echo "      VFS path redirection for modules" >> "$KERNEL_DIR/fs/Kconfig"
        echo "  ✅ Added to fs/Kconfig"
    else
        echo "  ⏭️  Already in fs/Kconfig"
    fi
fi

echo ""
echo "========================================"
echo "⚠️  MANUAL STEP REQUIRED:"
echo "========================================"
echo ""
echo "1. Edit fs/namei.c:"
echo "   Find getname_flags() function"
echo "   Add these lines BEFORE 'return result;':"
echo ""
echo "   #ifdef CONFIG_MOUNTZERO"
echo "   #include <linux/mountzero_vfs.h>"
echo "   result = mountzero_vfs_getname_hook(result);"
echo "   #endif"
echo ""
echo "2. Add to your defconfig:"
echo "   CONFIG_MOUNTZERO=y"
echo ""
echo "   ⚠️  Also ensure: CONFIG_KSU_SUSFS=y"
echo ""
echo "3. Build:"
echo "   make -j$(nproc)"
echo ""
echo "4. Flash boot.img + install module.zip"
echo ""
echo "========================================"
echo "✅ Integration files copied!"
echo "========================================"