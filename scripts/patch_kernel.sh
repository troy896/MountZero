#!/bin/bash
# MountZero VFS - Kernel Patcher
# Applies MountZero VFS patches to a kernel source tree
#
# Usage: ./patch_kernel.sh /path/to/kernel/source
#
# Prerequisites:
#   - Kernel already has SUSFS v2.1.0 patches applied
#   - Kernel has KernelSU or APatch integrated
#
# What this script does:
#   1. Copies MountZero source files to kernel tree
#   2. Updates fs/Makefile to build mountzero
#   3. Updates fs/Kconfig to add CONFIG_MOUNTZERO
#   4. Hooks MountZero into fs/namei.c for VFS path interception
#
# After patching, add CONFIG_MOUNTZERO=y to your defconfig

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${1:-}"
SRC_FILES="$SCRIPT_DIR/../kernel/source_files"

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
echo "  MountZero VFS Kernel Patcher"
echo "============================================="
echo ""
echo "Target: $SOURCE_DIR"
echo "Source: $SRC_FILES"
echo ""

# ============================================================
# Step 1: Copy MountZero Source Files
# ============================================================
echo "[1/4] Installing MountZero VFS driver source files..."

if [ ! -d "$SRC_FILES" ]; then
    echo "  ❌ Source files not found at: $SRC_FILES"
    exit 1
fi

# Copy fs/ files
for f in mountzero.c mountzero_vfs.c; do
    if [ -f "$SRC_FILES/fs/$f" ]; then
        cp "$SRC_FILES/fs/$f" "$SOURCE_DIR/fs/$f"
        echo "  ✅ fs/$f installed ($(wc -l < "$SRC_FILES/fs/$f") lines)"
    fi
done

# Copy headers
for f in mountzero.h mountzero_def.h mountzero_vfs.h; do
    if [ -f "$SRC_FILES/include/linux/$f" ]; then
        cp "$SRC_FILES/include/linux/$f" "$SOURCE_DIR/include/linux/$f"
        echo "  ✅ include/linux/$f installed"
    fi
done

echo ""

# ============================================================
# Step 2: Update fs/Makefile
# ============================================================
echo "[2/4] Updating fs/Makefile..."

if grep -q "CONFIG_MOUNTZERO" "$SOURCE_DIR/fs/Makefile" 2>/dev/null; then
    echo "  ℹ️  fs/Makefile already has MOUNTZERO, skipping"
else
    # Find the right place to insert (after obj-$(CONFIG_NLS) or similar)
    if grep -q "obj-.*CONFIG_NLS" "$SOURCE_DIR/fs/Makefile" 2>/dev/null; then
        sed -i '/obj-.*CONFIG_NLS/a obj-$(CONFIG_MOUNTZERO)\t\t+= mountzero.o mountzero_vfs.o' \
            "$SOURCE_DIR/fs/Makefile"
    elif grep -q "obj-.*CONFIG_PROC_FS" "$SOURCE_DIR/fs/Makefile" 2>/dev/null; then
        sed -i '/obj-.*CONFIG_PROC_FS/a obj-$(CONFIG_MOUNTZERO)\t\t+= mountzero.o mountzero_vfs.o' \
            "$SOURCE_DIR/fs/Makefile"
    else
        # Fallback: append to end
        printf '\nobj-$(CONFIG_MOUNTZERO)\t\t+= mountzero.o mountzero_vfs.o\n' >> "$SOURCE_DIR/fs/Makefile"
    fi
    echo "  ✅ fs/Makefile updated"
fi

echo ""

# ============================================================
# Step 3: Update fs/Kconfig
# ============================================================
echo "[3/4] Updating fs/Kconfig..."

if ! grep -q "config MOUNTZERO" "$SOURCE_DIR/fs/Kconfig" 2>/dev/null; then
    cat >> "$SOURCE_DIR/fs/Kconfig" << 'KCONFIG'

config MOUNTZERO
    bool "MountZero VFS Path Redirection System"
    depends on KSU_SUSFS
    default y
    help
      VFS-level path redirection for KernelSU modules.
      Works alongside SUSFS v2.1.0 to provide:
      - Automatic module mounting at boot
      - Path redirection without overlayfs
      - Virtual directory injection
      - Fast bloom filter lookups
      - Hot-plug module detection
      - SUSFS bridge integration
      - BRENE root evasion engine
      - Direct uname spoofing
      - Bootloop guard
KCONFIG
    echo "  ✅ fs/Kconfig updated"
else
    echo "  ℹ️  fs/Kconfig already has MOUNTZERO, skipping"
fi

echo ""

# ============================================================
# Step 4: Hook MountZero into fs/namei.c
# ============================================================
echo "[4/4] Integrating VFS hooks into fs/namei.c..."

NAMEI="$SOURCE_DIR/fs/namei.c"

if grep -q "mountzero_vfs_getname_hook" "$NAMEI" 2>/dev/null; then
    echo "  ℹ️  fs/namei.c already has MountZero hooks, skipping"
else
    # Add include after SUSFS includes
    if grep -q "susfs.h" "$NAMEI" 2>/dev/null; then
        sed -i '/#include <linux\/susfs.h>/a #ifdef CONFIG_MOUNTZERO\n#include <linux/mountzero_vfs.h>\n#endif' \
            "$NAMEI"
        echo "  ✅ Added mountzero_vfs.h include"
    elif grep -q "ksu.h" "$NAMEI" 2>/dev/null; then
        sed -i '/#include <linux\/ksu.h>/a #ifdef CONFIG_MOUNTZERO\n#include <linux/mountzero_vfs.h>\n#endif' \
            "$NAMEI"
        echo "  ✅ Added mountzero_vfs.h include"
    else
        # Add at top after fs.h
        sed -i '/#include <linux\/fs.h>/a #ifdef CONFIG_MOUNTZERO\n#include <linux/mountzero_vfs.h>\n#endif' \
            "$NAMEI"
        echo "  ✅ Added mountzero_vfs.h include"
    fi

    # Add hook in getname_flags() — the main path resolution function
    if grep -q "return result;" "$NAMEI" 2>/dev/null; then
        sed -i '/if (result->error)/i\
#ifdef CONFIG_MOUNTZERO\n\
\t/* MountZero VFS path redirection */\n\
\tresult = mountzero_vfs_getname_hook(result);\n\
#endif' "$NAMEI"
        echo "  ✅ Added getname_flags() hook"
    else
        echo "  ⚠️  Could not auto-detect hook insertion point"
        echo "  Please manually add the following in fs/namei.c getname_flags():"
        echo ""
        echo "    #ifdef CONFIG_MOUNTZERO"
        echo "    result = mountzero_vfs_getname_hook(result);"
        echo "    #endif"
    fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================="
echo "  ✅ MountZero VFS Patching Complete!"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Add to your defconfig:"
echo "     CONFIG_MOUNTZERO=y"
echo "     (Ensure CONFIG_KSU_SUSFS=y is already set)"
echo ""
echo "  2. Build kernel:"
echo "     make -j\$(nproc) 2>&1 | tee build.log"
echo ""
echo "  3. Flash kernel and MountZero_Manager module"
echo "     📥 https://github.com/mafiadan6/MountZero/releases"
echo ""
echo "  4. Reboot device"
echo ""
echo "  💬 Telegram: https://t.me/mastermindszs"
echo ""
