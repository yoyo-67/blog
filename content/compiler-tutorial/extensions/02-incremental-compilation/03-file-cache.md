---
title: "2.3: File Cache"
weight: 3
---

# Lesson 2.3: File Cache (ZirCache)

Now let's build a cache that stores compiled LLVM IR for entire files using Git-style content-addressed storage.

---

## Goal

Build a `ZirCache` that:
- Stores LLVM IR output per file
- Uses combined hash (file + dependencies) as the key
- Stores objects in Git-style directory structure
- Supports fast lookup via an index file

---

## Why Git-Style Storage?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         GIT-STYLE vs FLAT STORAGE                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   FLAT STORAGE:                                                              │
│   .cache/                                                                    │
│   ├── 3db3b7314a73226b.ll                                                   │
│   ├── 9a2eb98b6d927e93.ll                                                   │
│   └── ... (thousands of files in one directory)                             │
│                                                                              │
│   Problem: Large directories are SLOW on many filesystems                    │
│                                                                              │
│   GIT-STYLE STORAGE:                                                         │
│   .cache/zir/                                                               │
│   ├── 3d/                                                                   │
│   │   └── b3b7314a73226b                                                    │
│   ├── 9a/                                                                   │
│   │   └── 2eb98b6d927e93                                                    │
│   └── ...                                                                   │
│                                                                              │
│   First 2 hex chars = subdirectory (256 possible)                           │
│   Remaining chars = filename                                                 │
│   Each directory has ~1/256th of the files = much faster!                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## ZirCache Structure

```
ZirCache {
    cache_dir:     string,           // e.g., ".mini_cache"
    index:         Map<path, u64>,   // path -> combined_hash
    loaded_count:  usize,            // stats
}
```

The index maps file paths to their combined hash. The actual LLVM IR is stored in object files keyed by hash.

---

## Step 1: Hash to Path Conversion

Convert a 64-bit hash to a Git-style path:

```
hashToPath(cache_dir, hash) -> string {
    // Convert hash to 16-char hex string
    hex = format("{:016x}", hash)

    // First 2 chars = subdirectory, rest = filename
    // Example: 0x3db3b7314a73226b -> "zir/3d/b3b7314a73226b"
    return format("{}/zir/{}/{}", cache_dir, hex[0..2], hex[2..16])
}
```

Example:
```
hash = 0x3db3b7314a73226b

hashToPath(".mini_cache", hash)
→ ".mini_cache/zir/3d/b3b7314a73226b"
```

---

## Step 2: Initialize ZirCache

```
ZirCache.init(cache_dir) -> ZirCache {
    return ZirCache {
        cache_dir: cache_dir,
        index: empty_map,
        loaded_count: 0,
    }
}
```

---

## Step 3: Store LLVM IR

```
ZirCache.put(self, path, combined_hash, llvm_ir) {
    // Update index
    self.index.put(path, combined_hash)

    // Compute object path
    object_path = hashToPath(self.cache_dir, combined_hash)

    // Ensure subdirectory exists
    mkdir_p(dirname(object_path))

    // Write LLVM IR to object file
    write_file(object_path, llvm_ir)
}
```

---

## Step 4: Check for Cache Hit

```
ZirCache.hasMatchingHash(self, path, combined_hash) -> bool {
    if self.index.get(path) -> cached_hash {
        return cached_hash == combined_hash
    }
    return false
}
```

This is the key insight: we use the **combined hash** (which includes all transitive dependencies) as the key. If ANY dependency changed, the combined hash changes, and we get a cache miss.

---

## Step 5: Retrieve LLVM IR

```
ZirCache.getLlvmIr(self, path, combined_hash) -> string | null {
    // Check if hash matches
    if not self.hasMatchingHash(path, combined_hash) {
        return null  // Cache miss
    }

    // Read from object file
    object_path = hashToPath(self.cache_dir, combined_hash)

    if file_exists(object_path) {
        return read_file(object_path)
    }

    return null
}
```

---

## Step 6: Save/Load Index

The index maps paths to hashes - save it in binary format:

```
ZirCache.save(self) {
    index_path = format("{}/zir_index.bin", self.cache_dir)
    file = create_file(index_path)

    // Write entry count
    file.writeU32(self.index.count())

    for (path, hash) in self.index {
        // Write path (length-prefixed)
        file.writeU32(path.len)
        file.writeBytes(path)

        // Write hash
        file.writeU64(hash)
    }
}

ZirCache.load(self) {
    index_path = format("{}/zir_index.bin", self.cache_dir)

    if not file_exists(index_path) {
        return
    }

    file = open_file(index_path)
    count = file.readU32()

    for _ in 0..count {
        path_len = file.readU32()
        path = file.readBytes(path_len)
        hash = file.readU64()

        self.index.put(path, hash)
        self.loaded_count += 1
    }
}
```

---

## Combined IR Storage

For surgical patching (covered in lesson 5), we also store the "combined IR" - the complete LLVM IR output with file markers:

```
ZirCache.putCombinedIr(self, path, llvm_ir) {
    // Store in combined/ directory (not hash-based)
    combined_path = format("{}/combined/{}.ll",
        self.cache_dir,
        sanitize_filename(path))

    mkdir_p(dirname(combined_path))
    write_file(combined_path, llvm_ir)
}

ZirCache.getCombinedIr(self, path) -> string | null {
    combined_path = format("{}/combined/{}.ll",
        self.cache_dir,
        sanitize_filename(path))

    if file_exists(combined_path) {
        return read_file(combined_path)
    }
    return null
}
```

---

## Complete Cache Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         ZIRCACHE FLOW                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   BUILD REQUEST for main.mini                                                │
│                                                                              │
│   1. Compute combined_hash                                                   │
│      ├── Hash main.mini source                                              │
│      ├── Hash math.mini source (import)                                     │
│      └── Hash utils.mini source (transitive import)                         │
│      = 0x3db3b7314a73226b                                                   │
│                                                                              │
│   2. Check cache                                                             │
│      cache.hasMatchingHash("main.mini", 0x3db3b7314a73226b)                 │
│      ├── index["main.mini"] = 0x3db3b7314a73226b? YES                       │
│      └── CACHE HIT!                                                          │
│                                                                              │
│   3. Retrieve cached IR                                                      │
│      cache.getLlvmIr("main.mini", 0x3db3b7314a73226b)                       │
│      ├── path = ".mini_cache/zir/3d/b3b7314a73226b"                         │
│      └── return read_file(path)                                             │
│                                                                              │
│   NO COMPILATION NEEDED!                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
.mini_cache/
├── zir_index.bin              # path -> combined_hash mapping
├── zir/                       # Git-style object storage
│   ├── 3d/
│   │   └── b3b7314a73226b     # LLVM IR for hash 0x3d...
│   ├── 9a/
│   │   └── 2eb98b6d927e93     # LLVM IR for hash 0x9a...
│   └── ff/
│       └── 53f68c13783d1c     # LLVM IR for hash 0xff...
└── combined/                  # Full IRs for surgical patching
    └── main.mini.ll           # Complete output with markers
```

---

## Verify Your Implementation

### Test 1: Hash to path conversion
```
hash = 0x3db3b7314a73226b
path = hashToPath(".cache", hash)

Check: path == ".cache/zir/3d/b3b7314a73226b"
```

### Test 2: Store and retrieve
```
cache = ZirCache.init(".test_cache")

llvm_ir = "define i32 @main() { ret i32 42 }"
cache.put("test.mini", 0x123456, llvm_ir)

retrieved = cache.getLlvmIr("test.mini", 0x123456)
Check: retrieved == llvm_ir
```

### Test 3: Cache miss on hash change
```
cache = ZirCache.init(".test_cache")
cache.put("test.mini", 0x123456, "old ir")

// Different hash = cache miss
retrieved = cache.getLlvmIr("test.mini", 0x999999)
Check: retrieved == null
```

### Test 4: Save and load
```
cache1 = ZirCache.init(".test_cache")
cache1.put("a.mini", 0x111, "ir_a")
cache1.put("b.mini", 0x222, "ir_b")
cache1.save()

cache2 = ZirCache.init(".test_cache")
cache2.load()

Check: cache2.hasMatchingHash("a.mini", 0x111) == true
Check: cache2.hasMatchingHash("b.mini", 0x222) == true
```

### Test 5: Git-style directories created
```
cache = ZirCache.init(".test_cache")
cache.put("test.mini", 0xaabbccdd11223344, "ir")

Check: file_exists(".test_cache/zir/aa/bbccdd11223344")
```

---

## What's Next

File-level caching is great, but we can be even more granular. Let's cache individual functions.

Next: [Lesson 2.4: Function Cache](../04-function-cache/) →
