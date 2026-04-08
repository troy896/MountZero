# MountZero VFS Kernel Source Files

## Files to copy to kernel tree

### fs/
- `mountzero.c` — Core VFS driver (1350 lines)
- `mountzero_vfs.c` — VFS hooks (300 lines)

### include/linux/
- `mountzero.h` — Public IOCTL interface
- `mountzero_def.h` — Internal definitions
- `mountzero_vfs.h` — VFS hook declarations

## Build integration
- `fs/Makefile`: Add `obj-$(CONFIG_MOUNTZERO) += mountzero.o mountzero_vfs.o`
- `fs/Kconfig`: Add CONFIG_MOUNTZERO entry (see docs/KERNEL_INTEGRATION.md)
- `fs/namei.c`: Add mountzero_vfs_getname_hook() hook
