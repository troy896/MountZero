#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Improved Script to apply susfs patch modifications to task_mmu.c
"""

import os
import sys
import re
import shutil
from datetime import datetime

def create_backup(original_file):
    """Create a backup of the original file"""
    backup_file = original_file + '.backup.' + datetime.now().strftime('%Y%m%d_%H%M%S')
    if os.path.exists(original_file):
        shutil.copy2(original_file, backup_file)
        print(f"✓ Backup created: {backup_file}")
        return backup_file
    return None

def apply_susfs_patch(input_file, output_file=None):
    """
    Apply susfs patch to task_mmu.c file with improved pattern matching
    """
    if output_file is None:
        output_file = input_file
    
    # Read the original file
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    modified_lines = []
    
    # Track patches
    patches_applied = {
        'include': False,
        'size_patch': False,
        'vmflags_patch': False,
        'bypass_label1': False,
        'bypass_label2': False
    }
    
    i = 0
    while i < len(lines):
        line = lines[i]
        matched = False
        
        # ============================================        # PATCH 1: Add susfs_def.h include after ctype.h
        # ============================================
        if not patches_applied['include'] and 'ctype.h' in line and '#include' in line:
            modified_lines.append(line)
            modified_lines.append('#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)')
            modified_lines.append('#include <linux/susfs_def.h>')
            modified_lines.append('#endif')
            patches_applied['include'] = True
            print("  ✓ Added susfs_def.h include")
            i += 1
            continue
        
        # ============================================
        # PATCH 2: Add SUS_MAP check for Size/PageSize in show_smap
        # Look for seq_printf with "Size:
        # ============================================
        if not patches_applied['size_patch'] and 'seq_printf(m,' in line:
            # Check next few lines for "Size:
            found_size = False
            for j in range(i, min(i+5, len(lines))):
                if '"Size:' in lines[j] or '"Size:' in lines[j]:
                    found_size = True
                    break
            
            if found_size:
                # Add the SUS_MAP check before seq_printf
                modified_lines.append('#ifdef CONFIG_KSU_SUSFS_SUS_MAP')
                modified_lines.append('\tif (vma->vm_file) {')
                modified_lines.append('\t\tstruct inode *inode = file_inode(vma->vm_file);')
                modified_lines.append('\t\tif (SUSFS_IS_INODE_SUS_MAP(inode)) {')
                modified_lines.append('\t\t\tseq_printf(m,')
                modified_lines.append('\t\t\t\t"Size:           %8lu kB\\n"')
                modified_lines.append('\t\t\t\t"KernelPageSize: %8lu kB\\n"')
                modified_lines.append('\t\t\t\t"MMUPageSize:    %8lu kB\\n",')
                modified_lines.append('\t\t\t\t(vma->vm_end - vma->vm_start) >> 10,')
                modified_lines.append('\t\t\t\t4, 4);')
                modified_lines.append('\t\t\tgoto bypass_orig_flow;')
                modified_lines.append('\t\t}')
                modified_lines.append('\t}')
                modified_lines.append('#endif')
                modified_lines.append(line)
                patches_applied['size_patch'] = True
                print("  ✓ Added SUS_MAP Size patch")
                i += 1
                continue
        
        # ============================================
        # PATCH 3: Add bypass_orig_flow label after vma_mmu_pagesize
        # ============================================
        if not patches_applied['bypass_label1'] and 'vma_mmu_pagesize(vma)' in line:
            modified_lines.append(line)
            modified_lines.append('')
            modified_lines.append('#ifdef CONFIG_KSU_SUSFS_SUS_MAP')
            modified_lines.append('bypass_orig_flow:')
            modified_lines.append('#endif')
            patches_applied['bypass_label1'] = True
            print("  ✓ Added bypass_orig_flow label")
            i += 1
            continue
        
        # ============================================
        # PATCH 4: Add SUS_MAP check for VmFlags before arch_show_smap
        # ============================================
        if not patches_applied['vmflags_patch'] and 'arch_show_smap(m, vma)' in line:
            # Add the SUS_MAP check before arch_show_smap
            modified_lines.append('#ifdef CONFIG_KSU_SUSFS_SUS_MAP')
            modified_lines.append('\tif (vma->vm_file) {')
            modified_lines.append('\t\tstruct inode *inode = file_inode(vma->vm_file);')
            modified_lines.append('\t\tif (SUSFS_IS_INODE_SUS_MAP(inode)) {')
            modified_lines.append('\t\t\tseq_puts(m, "VmFlags: mr mw me\\n");')
            modified_lines.append('\t\t\tgoto bypass_orig_flow2;')
            modified_lines.append('\t\t}')
            modified_lines.append('\t}')
            modified_lines.append('#endif')
            modified_lines.append(line)
            patches_applied['vmflags_patch'] = True
            print("  ✓ Added SUS_MAP VmFlags patch")
            i += 1
            continue
        
        # ============================================
        # PATCH 5: Add bypass_orig_flow2 label after show_smap_vma_flags
        # ============================================
        if not patches_applied['bypass_label2'] and 'show_smap_vma_flags(m, vma)' in line:
            modified_lines.append(line)
            modified_lines.append('')
            modified_lines.append('#ifdef CONFIG_KSU_SUSFS_SUS_MAP')
            modified_lines.append('bypass_orig_flow2:')
            modified_lines.append('#endif')
            patches_applied['bypass_label2'] = True
            print("  ✓ Added bypass_orig_flow2 label")
            i += 1
            continue
        
        # ============================================
        # Default: just add the line as is
        # ============================================
        modified_lines.append(line)
        i += 1
        # Write the modified content
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(modified_lines))
    
    print(f"\n✓ Patch applied successfully to: {output_file}")
    
    # Summary
    print("\n" + "=" * 60)
    print("  PATCH SUMMARY")
    print("=" * 60)
    all_success = True
    for patch_name, status in patches_applied.items():
        symbol = '✓' if status else '✗'
        print(f"  {symbol} {patch_name}")
        if not status:
            all_success = False
    
    return all_success


def verify_patch(input_file):
    """Verify that patches were applied correctly"""
    print("\n" + "=" * 60)
    print("  VERIFICATION")
    print("=" * 60)
    
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    checks = [
        ('susfs_def.h include', '#include <linux/susfs_def.h>'),
        ('SUSFS_IS_INODE_SUS_MAP', 'SUSFS_IS_INODE_SUS_MAP'),
        ('bypass_orig_flow label', 'bypass_orig_flow:'),
        ('bypass_orig_flow2 label', 'bypass_orig_flow2:'),
        ('CONFIG_KSU_SUSFS_SUS_MAP', 'CONFIG_KSU_SUSFS_SUS_MAP'),
    ]
    
    all_passed = True
    for name, pattern in checks:
        if pattern in content:
            print(f"  ✓ {name}")
        else:
            print(f"  ✗ {name}")
            all_passed = False
    
    return all_passed


def main():
    print("=" * 60)
    print("  SUSFS Patch Auto-Apply Script for task_mmu.c")
    print("  (Improved Version)")
    print("=" * 60)
    print()
    
    # Default file path
    default_file = "task_mmu.c"
    
    # Check if file exists
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    else:
        input_file = default_file
    
    if not os.path.exists(input_file):
        print(f"✗ Error: File '{input_file}' not found!")
        print(f"  Usage: python3 {sys.argv[0]} [path/to/task_mmu.c]")
        sys.exit(1)
    
    # Create backup
    create_backup(input_file)
    
    # Apply patch
    print(f"\nApplying patch to: {input_file}\n")
    
    try:
        success = apply_susfs_patch(input_file)
        
        # Verify
        verify_patch(input_file)
        
        print("\n" + "=" * 60)
        if success:
            print("  ✓ Patch application completed successfully!")
        else:
            print("  ⚠ Some patches may not have been applied correctly")
            print("  Please check the file manually")
        print("=" * 60)
        
    except Exception as e:
        print(f"\n✗ Error applying patch: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
