/*
 * MountZero - Internal Definitions
 * 
 * Data structures and constants used internally by MountZero.
 */

#ifndef __LINUX_MOUNTZERO_DEF_H
#define __LINUX_MOUNTZERO_DEF_H

#include <linux/types.h>
#include <linux/list.h>
#include <linux/hashtable.h>
#include <linux/spinlock.h>
#include <linux/atomic.h>
#include <linux/uidgid.h>
#include <linux/bitops.h>

#define MOUNTZERO_HASH_BITS 10
#define MZ_BLOOM_BITS 8192
#define MZ_BLOOM_MASK (MZ_BLOOM_BITS - 1)

#define MOUNTZERO_VERSION "1.0.0"

/* Rule flags */
#define MZ_FLAG_READ_ONLY    (1 << 0)
#define MZ_FLAG_HIDE_ORIGINAL (1 << 1)
#define MZ_FLAG_PERMANENT    (1 << 2)
#define MZ_FLAG_DYNAMIC      (1 << 3)

/* Rule structure for hash tables */
struct mz_rule {
    char *virtual_path;
    char *real_path;
    unsigned int flags;
    u32 hash;
    struct hlist_node node;
    struct hlist_node ino_node;  /* For inode hash table */
    u64 real_ino;                /* Real file inode number */
    u64 real_dev;                /* Real file device */
    u64 v_ino;                   /* Spoofed inode number */
    u64 v_dev;                   /* Spoofed device */
};

/* External declarations for global state */
extern atomic_t mountzero_enabled;
extern int mountzero_debug_level;
extern spinlock_t mz_lock;
extern struct hlist_head mz_redirect_rules_ht[1 << MOUNTZERO_HASH_BITS];
extern struct hlist_head mz_ino_ht[1 << MOUNTZERO_HASH_BITS];

/* Bloom filter helpers */
static inline void mz_bloom_add(u32 hash);
static inline bool mz_bloom_test(u32 hash);

#endif /* __LINUX_MOUNTZERO_DEF_H */
