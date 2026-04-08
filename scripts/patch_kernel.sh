#!/bin/bash
# MountZero VFS + SUSFS - Complete Kernel Patcher
# Applies SUSFS + MountZero VFS patches to a kernel source tree
#
# Usage: ./patch_kernel.sh /path/to/kernel/source
#
# Patches applied:
#   1. SUSFS core patch (susfs_patch_to_4.14.patch)
#   2. SUSFS inline hooks (namei.c, d_path.c, proc, etc.)
#   3. MountZero VFS driver (source files + build integration)
#
# After patching, add to defconfig:
#   CONFIG_KSU_SUSFS=y
#   CONFIG_KSU_SUSFS_SUS_PATH=y
#   CONFIG_KSU_SUSFS_SUS_MOUNT=y
#   CONFIG_KSU_SUSFS_SUS_KSTAT=y
#   CONFIG_KSU_SUSFS_SPOOF_UNAME=y
#   CONFIG_KSU_SUSFS_ENABLE_LOG=y
#   CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
#   CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
#   CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
#   CONFIG_KSU_SUSFS_SUS_MAP=y
#   CONFIG_MOUNTZERO=y
#
# License: GPL v2.0
# Author: 爪卂丂ㄒ乇尺爪工刀ᗪ丂

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${1:-}"
PATCH_DIR="$SCRIPT_DIR/../kernel/patches"
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
echo "  MountZero VFS + SUSFS Kernel Patcher"
echo "============================================="
echo ""
echo "Target: $SOURCE_DIR"
echo "Patches: $PATCH_DIR"
echo "Source: $SRC_FILES"
echo ""

# ============================================================
# Step 1: Apply SUSFS Core Patch
# ============================================================
echo "[1/6] Applying SUSFS core patch..."

if [ -f "$PATCH_DIR/001_susfs_patch_to_4.14.patch" ]; then
    cd "$SOURCE_DIR"
    if patch -p1 --dry-run < "$PATCH_DIR/001_susfs_patch_to_4.14.patch" >/dev/null 2>&1; then
        patch -p1 < "$PATCH_DIR/001_susfs_patch_to_4.14.patch"
        echo "  ✅ SUSFS core patch applied"
    else
        echo "  ⚠️  SUSFS patch failed dry-run, applying with fuzz..."
        patch -p1 --fuzz=3 < "$PATCH_DIR/001_susfs_patch_to_4.14.patch" || echo "  ⚠️  Some SUSFS hunks skipped"
    fi
else
    echo "  ⚠️  SUSFS patch not found, copying source files directly..."
    # Fallback: copy SUSFS source files
    if [ -f "$SRC_FILES/fs/susfs.c" ]; then
        cp "$SRC_FILES/fs/susfs.c" "$SOURCE_DIR/fs/susfs.c"
        echo "  ✅ fs/susfs.c installed"
    fi
    if [ -f "$SRC_FILES/include/linux/susfs.h" ]; then
        cp "$SRC_FILES/include/linux/susfs.h" "$SOURCE_DIR/include/linux/susfs.h"
        echo "  ✅ include/linux/susfs.h installed"
    fi
    if [ -f "$SRC_FILES/include/linux/susfs_def.h" ]; then
        cp "$SRC_FILES/include/linux/susfs_def.h" "$SOURCE_DIR/include/linux/susfs_def.h"
        echo "  ✅ include/linux/susfs_def.h installed"
    fi
fi

echo ""

# ============================================================
# Step 2: Apply SUSFS Inline Hooks
# ============================================================
echo "[2/6] Applying SUSFS inline hooks (namei.c, d_path.c, etc.)..."

if [ -f "$SCRIPT_DIR/susfs_inline_hook_patches.sh" ]; then
    chmod +x "$SCRIPT_DIR/susfs_inline_hook_patches.sh"
    cd "$SOURCE_DIR"
    if bash "$SCRIPT_DIR/susfs_inline_hook_patches.sh" 2>&1 | tail -5; then
        echo "  ✅ SUSFS inline hooks applied"
    else
        echo "  ⚠️  SUSFS inline hook script had issues, continuing..."
    fi
else
    echo "  ℹ️  No inline hook script found, applying manually..."
    
    # Apply SUSFS hooks to fs/namei.c
    NAMEI="$SOURCE_DIR/fs/namei.c"
    if [ -f "$NAMEI" ]; then
        if ! grep -q "CONFIG_KSU_SUSFS_SUS_PATH" "$NAMEI" 2>/dev/null; then
            echo "  ℹ️  Applying SUSFS hooks to namei.c manually..."
            # Add SUSFS include
            sed -i '/#include <linux\/fs_struct.h>/a #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#include <linux/susfs_def.h>\n#endif' "$NAMEI"
            echo "  ✅ Added SUSFS includes to namei.c"
        else
            echo "  ℹ️  namei.c already has SUSFS hooks"
        fi
    fi
    
    # Apply SUSFS hooks to fs/d_path.c
    DPATH="$SOURCE_DIR/fs/d_path.c"
    if [ -f "$DPATH" ]; then
        if ! grep -q "CONFIG_KSU_SUSFS" "$DPATH" 2>/dev/null; then
            sed -i '/#include <linux\/fs.h>/a #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#endif' "$DPATH"
            echo "  ✅ Added SUSFS includes to d_path.c"
        fi
    fi
    
    # Apply SUSFS hooks to fs/readdir.c
    READDIR="$SOURCE_DIR/fs/readdir.c"
    if [ -f "$READDIR" ]; then
        if ! grep -q "CONFIG_KSU_SUSFS_SUS_PATH" "$READDIR" 2>/dev/null; then
            sed -i '/#include <linux\/fs.h>/a #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#endif' "$READDIR"
            echo "  ✅ Added SUSFS includes to readdir.c"
        fi
    fi
    
    # Apply SUSFS hooks to fs/proc/base.c
    PROCBASE="$SOURCE_DIR/fs/proc/base.c"
    if [ -f "$PROCBASE" ]; then
        if ! grep -q "CONFIG_KSU_SUSFS" "$PROCBASE" 2>/dev/null; then
            sed -i '/#include "internal.h"/a #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#endif' "$PROCBASE"
            echo "  ✅ Added SUSFS includes to fs/proc/base.c"
        fi
    fi
    
    # Apply SUSFS hooks to fs/proc/task_mmu.c
    TASKMMU="$SOURCE_DIR/fs/proc/task_mmu.c"
    if [ -f "$TASKMMU" ]; then
        if ! grep -q "CONFIG_KSU_SUSFS" "$TASKMMU" 2>/dev/null; then
            sed -i '/#include "internal.h"/a #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#endif' "$TASKMMU"
            echo "  ✅ Added SUSFS includes to fs/proc/task_mmu.c"
        fi
    fi
fi

echo ""

# ============================================================
# Step 3: Copy MountZero VFS Source Files
# ============================================================
echo "[3/6] Installing MountZero VFS driver source files..."

if [ ! -d "$SRC_FILES" ]; then
    echo "  ❌ Source files not found at: $SRC_FILES"
    exit 1
fi

# Copy fs/ files
for f in mountzero.c mountzero_vfs.c susfs.c; do
    if [ -f "$SRC_FILES/fs/$f" ]; then
        cp "$SRC_FILES/fs/$f" "$SOURCE_DIR/fs/$f"
        echo "  ✅ fs/$f installed ($(wc -l < "$SRC_FILES/fs/$f") lines)"
    fi
done

# Copy headers
for f in mountzero.h mountzero_def.h mountzero_vfs.h susfs.h susfs_def.h; do
    if [ -f "$SRC_FILES/include/linux/$f" ]; then
        cp "$SRC_FILES/include/linux/$f" "$SOURCE_DIR/include/linux/$f"
        echo "  ✅ include/linux/$f installed"
    fi
done

echo ""

# ============================================================
# Step 4: Update fs/Makefile
# ============================================================
echo "[4/6] Updating fs/Makefile..."

if ! grep -q "CONFIG_MOUNTZERO" "$SOURCE_DIR/fs/Makefile" 2>/dev/null; then
    if grep -q "obj-.*CONFIG_NLS" "$SOURCE_DIR/fs/Makefile" 2>/dev/null; then
        sed -i '/obj-.*CONFIG_NLS/a obj-$(CONFIG_MOUNTZERO)\t\t+= mountzero.o mountzero_vfs.o' \
            "$SOURCE_DIR/fs/Makefile"
    elif grep -q "obj-.*CONFIG_PROC_FS" "$SOURCE_DIR/fs/Makefile" 2>/dev/null; then
        sed -i '/obj-.*CONFIG_PROC_FS/a obj-$(CONFIG_MOUNTZERO)\t\t+= mountzero.o mountzero_vfs.o' \
            "$SOURCE_DIR/fs/Makefile"
    else
        printf '\nobj-$(CONFIG_MOUNTZERO)\t\t+= mountzero.o mountzero_vfs.o\n' >> "$SOURCE_DIR/fs/Makefile"
    fi
    echo "  ✅ fs/Makefile updated (mountzero)"
else
    echo "  ℹ️  fs/Makefile already has MOUNTZERO"
fi

if ! grep -q "CONFIG_KSU_SUSFS" "$SOURCE_DIR/fs/Makefile" 2>/dev/null && \
   [ -f "$SOURCE_DIR/fs/susfs.c" ]; then
    if grep -q "obj-.*CONFIG_KSU" "$SOURCE_DIR/fs/Makefile" 2>/dev/null; then
        sed -i '/obj-.*CONFIG_KSU/a obj-$(CONFIG_KSU_SUSFS)\t\t+= susfs.o' \
            "$SOURCE_DIR/fs/Makefile"
    else
        printf '\nobj-$(CONFIG_KSU_SUSFS)\t\t+= susfs.o\n' >> "$SOURCE_DIR/fs/Makefile"
    fi
    echo "  ✅ fs/Makefile updated (susfs)"
else
    echo "  ℹ️  fs/Makefile already has SUSFS"
fi

echo ""

# ============================================================
# Step 5: Update fs/Kconfig
# ============================================================
echo "[5/6] Updating fs/Kconfig..."

if ! grep -q "config MOUNTZERO" "$SOURCE_DIR/fs/Kconfig" 2>/dev/null; then
    cat >> "$SOURCE_DIR/fs/Kconfig" << 'KCONFIG'

config MOUNTZERO
    bool "MountZero VFS Path Redirection System"
    depends on KSU_SUSFS
    default y
    help
      VFS-level path redirection for KernelSU modules.
      Works alongside SUSFS to provide:
      - Automatic module mounting at boot
      - Path redirection without overlayfs
      - Virtual directory injection
      - Fast bloom filter lookups
      - Hot-plug module detection
      - SUSFS bridge integration
      - BRENE root evasion engine
KCONFIG
    echo "  ✅ fs/Kconfig updated (MOUNTZERO)"
else
    echo "  ℹ️  fs/Kconfig already has MOUNTZERO"
fi

echo ""

# ============================================================
# Step 6: Hook MountZero into fs/namei.c
# ============================================================
echo "[6/6] Integrating MountZero VFS hooks into fs/namei.c..."

NAMEI="$SOURCE_DIR/fs/namei.c"

if [ -f "$NAMEI" ]; then
    if grep -q "mountzero_vfs_getname_hook" "$NAMEI" 2>/dev/null; then
        echo "  ℹ️  fs/namei.c already has MountZero hooks"
    else
        # Add include after SUSFS includes
        if grep -q "susfs.h" "$NAMEI" 2>/dev/null; then
            sed -i '/#include <linux\/susfs.h>/a #ifdef CONFIG_MOUNTZERO\n#include <linux/mountzero_vfs.h>\n#endif' \
                "$NAMEI"
            echo "  ✅ Added mountzero_vfs.h include"
        else
            sed -i '/#include <linux\/fs.h>/a #ifdef CONFIG_MOUNTZERO\n#include <linux/mountzero_vfs.h>\n#endif' \
                "$NAMEI"
            echo "  ✅ Added mountzero_vfs.h include"
        fi

        # Add hook in getname_flags()
        if grep -q "return result;" "$NAMEI" 2>/dev/null; then
            sed -i '/if (result->error)/i\
#ifdef CONFIG_MOUNTZERO\n\
\t/* MountZero VFS path redirection */\n\
\tresult = mountzero_vfs_getname_hook(result);\n\
#endif' "$NAMEI"
            echo "  ✅ Added getname_flags() hook"
        else
            echo "  ⚠️  Could not auto-detect hook insertion point"
            echo "  Please manually add in getname_flags():"
            echo "    #ifdef CONFIG_MOUNTZERO"
            echo "    result = mountzero_vfs_getname_hook(result);"
            echo "    #endif"
        fi
    fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================="
echo "  ✅ Kernel Patching Complete!"
echo "============================================="
echo ""
echo "Add to your defconfig:"
echo ""
echo "  # SUSFS"
echo "  CONFIG_KSU_SUSFS=y"
echo "  CONFIG_KSU_SUSFS_SUS_PATH=y"
echo "  CONFIG_KSU_SUSFS_SUS_MOUNT=y"
echo "  CONFIG_KSU_SUSFS_SUS_KSTAT=y"
echo "  CONFIG_KSU_SUSFS_SPOOF_UNAME=y"
echo "  CONFIG_KSU_SUSFS_ENABLE_LOG=y"
echo "  CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"
echo "  CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y"
echo "  CONFIG_KSU_SUSFS_OPEN_REDIRECT=y"
echo "  CONFIG_KSU_SUSFS_SUS_MAP=y"
echo ""
echo "  # MountZero VFS"
echo "  CONFIG_MOUNTZERO=y"
echo ""
echo "Then build: make -j\$(nproc)"
echo ""
