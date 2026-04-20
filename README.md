# MountZero VFS

**Load modules without mounts - 3 steps**

---

## Preview

See how the manager works: **[preview.mp4](./preview.mp4)**

---

## What is this?

MountZero lets you use KernelSU modules without bind mounts. No entries in `/proc/mounts`, no traces.

Your module files appear as regular system files.

---

## Credits

This project builds on the incredible work from:

- **Super-Builders** (https://github.com/Enginex0/Super-Builders) - GKI kernel patches with SUSFS + ZeroMount
- **SUSFS** by simonpunk - the hiding framework this project uses
- **KernelSU** - root framework
- **ZeroMount** - VFS architecture inspiration

Thank you to the community for making this possible!

---

## Requirements

- Kernel with **SUSFS** already integrated (`CONFIG_KSU_SUSFS=y`)
- **KernelSU** or **ReSukiSU**
- Any Android kernel: **4.14, 5.4, 5.10, 5.15, 6.1, 6.x**

---

## Step by Step

### Step 1: Copy 5 Files to Kernel

```
From project/, copy these files to your kernel source:

project/kernel/mountzero.c    →  /fs/
project/kernel/mountzero_vfs.c →  /fs/
project/kernel/mountzero.h    →  /include/linux/
project/kernel/mountzero_def.h → /include/linux/
project/kernel/mountzero_vfs.h → /include/linux/
```

Or run the auto-script:
```bash
./project/integrate.sh
```

### Step 2: Edit Build Files

**File: `fs/Makefile`**
```makefile
# Add this line at the end:
obj-y += mountzero.o mountzero_vfs.o
```

**File: `fs/namei.c`**
```c
// Find getname_flags() function
// Add this before "return result;" in that function:

#ifdef CONFIG_MOUNTZERO
#include <linux/mountzero_vfs.h>
result = mountzero_vfs_getname_hook(result);
#endif
```

**File: your defconfig**
```
CONFIG_MOUNTZERO=y
CONFIG_KSU_SUSFS=y
```

### Step 3: Build, Flash, Install

```bash
# Build kernel
make -j$(nproc)

# Flash
fastboot flash boot boot.img

# Install module via KernelSU Manager
# Download ZIP → KernelSU → Modules → Install from storage
```

---

## After Reboot

1. Open KernelSU Manager
2. Go to Modules tab
3. Enable MountZero VFS
4. Reboot

---

## Done!

---

## CLI Commands (optional)

```bash
mzctl status              # Check if enabled
mzctl list               # Show redirect rules
mzctl add /system/bin/su /data/adb/modules/X/system/bin/su
mzctl del /system/bin/su
mzctl susfs add-path /data/adb/ksu
mzctl susfs set-uname '5.15.196-g5a9c3d' '#1 SMP'
```

---

## Troubleshooting

| Problem | Fix |
|--------|-----|
| Build error | Added both mountzero.c AND mountzero_vfs.c? |
| Bootloop | Hold Volume Up+Down to skip (guard protects after 3 tries) |
| WebUI missing | Install module.zip via KernelSU |
| SUSFS error | Ensure CONFIG_KSU_SUSFS=y in kernel |

---

## License

GPL v3.0 - See LICENSE file

---

## Version

v2.0.3

---

## Support

Telegram: [@mountzerozvfs](https://t.me/mountzerozvfs)