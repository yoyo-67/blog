---
title: "Module 2: File-Level Cache"
weight: 2
---

# Module 2: File-Level Cache (ZirCache)

You can detect file changes. Now what? You need to store and retrieve compiled output so you don't recompile unchanged files.

**What you'll build:**
- A simple map cache for compiled IR
- Git-style content-addressed storage for deduplication
- A fast lookup index (no file reads needed)
- Binary persistence for fast startup

---

## Sub-lesson 2.1: Simple Map Cache

### The Problem

When a file hasn't changed, we want to skip compilation entirely. But where do we get the output?

```
Current situation:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Build 1: main.mini → compile → LLVM IR                             │
│  Build 2: main.mini unchanged → compile again → same LLVM IR!       │
│                                                                     │
│  We're doing redundant work. Store the result!                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The Solution

Start with the simplest thing that works: a map from file path to cached output.

**Data Structures:**

```
CacheEntry {
    combined_hash: u64      // Hash of file + all dependencies
    llvm_ir: string         // The compiled output
}

SimpleCache {
    entries: Map<path, CacheEntry>
}
```

**Why combined_hash?**

Remember from Module 1: the `combined_hash` includes the file AND all its transitive dependencies. If we store LLVM IR keyed by `combined_hash`, we automatically invalidate when dependencies change.

**Cache Operations:**

```
SimpleCache.put(self, path, combined_hash, llvm_ir) {
    self.entries.put(path, CacheEntry {
        combined_hash: combined_hash,
        llvm_ir: llvm_ir,
    })
}

SimpleCache.get(self, path, combined_hash) -> string | null {
    if self.entries.get(path) -> entry {
        if entry.combined_hash == combined_hash {
            return entry.llvm_ir  // Cache hit!
        }
    }
    return null  // Cache miss
}
```

**Usage in Compilation:**

```
compileFile(cache, hash_cache, path, base_dir) -> string {
    // Compute combined hash (from Module 1)
    combined_hash = computeCombinedHash(hash_cache, path, base_dir)

    // Check cache
    if cache.get(path, combined_hash) -> cached_ir {
        return cached_ir  // Skip compilation!
    }

    // Cache miss - compile
    source = read_file(path)
    ir = compile(source)

    // Store for next time
    cache.put(path, combined_hash, ir)

    return ir
}
```

### Try It Yourself

1. Implement `SimpleCache` with `put()` and `get()`
2. Integrate with your compiler
3. Test:

```
// Test 1: Cache hit
cache = SimpleCache.init()
cache.put("test.mini", 0x123, "define i32 @main() { ret i32 42 }")

result = cache.get("test.mini", 0x123)
assert result == "define i32 @main() { ret i32 42 }"

// Test 2: Cache miss on different hash
result = cache.get("test.mini", 0x456)
assert result == null

// Test 3: Cache miss on unknown path
result = cache.get("unknown.mini", 0x123)
assert result == null
```

### Benchmark Data

| Scenario | Time |
|----------|------|
| Compile 1 file | ~0.5ms |
| Cache lookup | ~0.001ms |
| **Speedup per file** | **500x** |

For 10,000 files, that's 5 seconds saved on warm builds!

### Problems with SimpleCache

This works but has issues:
1. **Memory** - Storing 10K LLVM IR strings in memory is expensive
2. **No persistence** - Cache lost when program exits
3. **No deduplication** - Identical IR stored multiple times

Let's fix these in the next sub-lessons.

---

## Sub-lesson 2.2: Content-Addressed Storage

### The Problem

Storing LLVM IR in memory doesn't scale:
- 10,000 files × ~1KB average = 10MB in memory
- No persistence across builds
- Program must load everything at startup

### The Solution

Store LLVM IR on disk using **content-addressed storage** (like Git).

```
┌─────────────────────────────────────────────────────────────────────┐
│ CONTENT-ADDRESSED STORAGE                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Idea: Use the hash as the filename                                  │
│                                                                     │
│ combined_hash = 0x3db3b7314a73226b                                  │
│ filename = "3db3b7314a73226b"                                       │
│                                                                     │
│ Benefits:                                                           │
│ - Natural deduplication (same content = same hash = same file)      │
│ - No separate "content → location" mapping needed                   │
│ - Content verifiable by recomputing hash                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Git-Style Directory Structure:**

Flat directories with thousands of files are slow. Git solves this by using the first 2 hex characters as a subdirectory:

```
FLAT (slow):                    GIT-STYLE (fast):
.cache/                         .cache/zir/
├── 3db3b7314a73226b.ll         ├── 3d/
├── 9a2eb98b6d927e93.ll         │   └── b3b7314a73226b
├── ff53f68c13783d1c.ll         ├── 9a/
└── ... (10,000 files)          │   └── 2eb98b6d927e93
                                └── ff/
                                    └── 53f68c13783d1c

Each subdirectory has ~1/256 of files = stays fast!
```

**Implementation:**

```
// Convert hash to storage path
getObjectPath(cache_dir, hash) -> string {
    hex = format("{:016x}", hash)  // 16 hex chars
    return format("{}/zir/{}/{}", cache_dir, hex[0:2], hex[2:])
}

// Example:
// hash = 0x3db3b7314a73226b
// → ".cache/zir/3d/b3b7314a73226b"
```

**Write Object:**

```
putObject(cache_dir, hash, content) {
    path = getObjectPath(cache_dir, hash)

    // Create subdirectory if needed
    ensure_directory_exists(dirname(path))

    // Write content
    // Skip if already exists (content-addressed = immutable)
    if not file_exists(path) {
        write_file(path, content)
    }
}
```

**Read Object:**

```
getObject(cache_dir, hash) -> string | null {
    path = getObjectPath(cache_dir, hash)

    if file_exists(path) {
        return read_file(path)
    }
    return null
}
```

### Why This Works

```
┌─────────────────────────────────────────────────────────────────────┐
│ DEDUPLICATION IN ACTION                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Scenario: Two files have identical output                           │
│                                                                     │
│ file_a.mini (combined_hash: 0xabc...)  →  compile  →  "define ..."  │
│ file_b.mini (combined_hash: 0xabc...)  →  compile  →  "define ..."  │
│                                                                     │
│ Both get the SAME combined_hash (identical dependencies)            │
│ Both write to the SAME object file                                  │
│ Disk space: 1 file, not 2!                                          │
│                                                                     │
│ Common case: files that import the same library with no local code  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Implement `getObjectPath()`
2. Implement `putObject()` and `getObject()`
3. Test:

```
// Test 1: Path generation
path = getObjectPath(".cache", 0x3db3b7314a73226b)
assert path == ".cache/zir/3d/b3b7314a73226b"

// Test 2: Write and read
putObject(".cache", 0xabc123, "some content")
result = getObject(".cache", 0xabc123)
assert result == "some content"

// Test 3: Deduplication
putObject(".cache", 0xabc123, "same content")
putObject(".cache", 0xabc123, "same content")
// Only one file created
assert count_files(".cache/zir/ab/") == 1

// Test 4: Different hash = different file
putObject(".cache", 0xdef456, "different content")
assert count_files(".cache/zir/de/") == 1
```

### Benchmark Data

| Metric | In-Memory | Content-Addressed |
|--------|----------|-------------------|
| Memory usage | 10MB | ~0MB (on disk) |
| Startup time | 0ms | ~1ms (just check dir exists) |
| Duplicate storage | 100% | 0% (deduplicated) |

---

## Sub-lesson 2.3: Index for Fast Lookup

### The Problem

With content-addressed storage, we need to know if a cached entry exists BEFORE reading the file:

```
Current lookup:
1. Compute combined_hash
2. Generate object path
3. Try to open file
4. Read file contents
5. Return (or null if file doesn't exist)

Problems:
- File system operations are slow
- We do this for EVERY file, even when nothing changed
- 10,000 file existence checks = ~100ms
```

### The Solution

Keep an **in-memory index** that maps paths to combined hashes. We can check the index without touching the filesystem.

```
┌─────────────────────────────────────────────────────────────────────┐
│ INDEX = Fast path → hash lookup                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ index:                                                              │
│   "main.mini"  → 0x3db3b7314a73226b                                 │
│   "math.mini"  → 0x9a2eb98b6d927e93                                 │
│   "utils.mini" → 0xff53f68c13783d1c                                 │
│                                                                     │
│ To check if cache is valid:                                         │
│   1. Compute current combined_hash                                  │
│   2. Look up in index: O(1) hash lookup                             │
│   3. If matches: cache is valid!                                    │
│   4. No file system access needed!                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Updated Data Structure:**

```
ZirCache {
    cache_dir: string
    index: Map<path, u64>    // path → combined_hash
}
```

**Fast Hash Check:**

```
ZirCache.hasMatchingHash(self, path, combined_hash) -> bool {
    if self.index.get(path) -> cached_hash {
        return cached_hash == combined_hash
    }
    return false
}
```

**Updated Put/Get:**

```
ZirCache.put(self, path, combined_hash, llvm_ir) {
    // Update index
    self.index.put(path, combined_hash)

    // Write to content-addressed storage
    putObject(self.cache_dir, combined_hash, llvm_ir)
}

ZirCache.getLlvmIr(self, path, combined_hash) -> string | null {
    // Fast check: is this hash even in our index?
    if not self.hasMatchingHash(path, combined_hash) {
        return null  // Definitely a miss
    }

    // Index says it should exist - read from disk
    return getObject(self.cache_dir, combined_hash)
}
```

**Complete Build Flow:**

```
// Fast path - check index first
if zir_cache.hasMatchingHash("main.mini", combined_hash) {
    // Index says we have this exact version cached
    // We might not even need to read it yet!
    // (depends on whether we're doing surgical patching)
}

// When we actually need the IR:
ir = zir_cache.getLlvmIr("main.mini", combined_hash)
```

### Try It Yourself

1. Add `index: Map<path, u64>` to your cache
2. Implement `hasMatchingHash()`
3. Update `put()` to update the index
4. Test:

```
// Test: Index lookup is fast
cache = ZirCache.init(".cache")
cache.put("a.mini", 0x111, "ir_a")
cache.put("b.mini", 0x222, "ir_b")

// These are O(1) hash lookups, no file I/O!
assert cache.hasMatchingHash("a.mini", 0x111) == true
assert cache.hasMatchingHash("a.mini", 0x999) == false
assert cache.hasMatchingHash("unknown.mini", 0x111) == false
```

### Benchmark Data

| Operation | Without Index | With Index |
|-----------|--------------|------------|
| Check cache validity | ~10μs (file stat) | ~0.1μs (hash lookup) |
| 10K checks | ~100ms | ~1ms |
| **Speedup** | - | **100x** |

---

## Sub-lesson 2.4: Binary Index Persistence

### The Problem

The index is in memory. When the program exits, we lose it. On the next build, we'd have to scan the entire cache directory to rebuild the index.

```
Without persistence:
1. Start build
2. Index is empty (lost on exit)
3. For each file: "Is it cached?" → Must check filesystem
4. Slow startup every time!
```

### The Solution

Save the index to a binary file. Load it at startup.

**Binary Format:**

```
┌────────────────────────────────────────────────────────────────────┐
│ ZIR INDEX BINARY FORMAT                                            │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ Header:                                                            │
│   [8 bytes] entry_count (u64, little-endian)                       │
│                                                                    │
│ For each entry:                                                    │
│   [4 bytes] path_length (u32)                                      │
│   [N bytes] path (UTF-8 string)                                    │
│   [8 bytes] combined_hash (u64, little-endian)                     │
│                                                                    │
│ Example (3 entries):                                               │
│   [0x03 0x00 0x00 0x00 0x00 0x00 0x00 0x00]  // count = 3          │
│   [0x0a 0x00 0x00 0x00]                      // path_len = 10      │
│   "main.mini"                                // path               │
│   [0x6b 0x22 0x73 0x4a 0x31 0xb7 0xb3 0x3d]  // hash              │
│   ... (next entry)                                                 │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Save Index:**

```
ZirCache.save(self) {
    path = format("{}/zir_index.bin", self.cache_dir)
    ensure_directory_exists(self.cache_dir)

    file = create_file(path)

    // Write count
    write_u64(file, self.index.count())

    // Write entries
    for (entry_path, hash) in self.index {
        // Write path
        write_u32(file, entry_path.length)
        write_bytes(file, entry_path)

        // Write hash
        write_u64(file, hash)
    }

    file.close()
}
```

**Load Index:**

```
ZirCache.load(self, cache_dir) {
    self.cache_dir = cache_dir
    path = format("{}/zir_index.bin", cache_dir)

    if not file_exists(path) {
        return  // No index yet
    }

    file = open_file(path)

    // Read count
    count = read_u64(file)

    // Read entries
    for _ in 0..count {
        // Read path
        path_len = read_u32(file)
        entry_path = read_bytes(file, path_len)

        // Read hash
        hash = read_u64(file)

        self.index.put(entry_path, hash)
    }

    file.close()
}
```

**Complete ZirCache:**

```
ZirCache {
    cache_dir: string
    index: Map<path, u64>

    init() -> ZirCache
    load(cache_dir)
    save()

    hasMatchingHash(path, combined_hash) -> bool
    put(path, combined_hash, llvm_ir)
    getLlvmIr(path, combined_hash) -> string | null
}
```

### Try It Yourself

1. Implement `save()` and `load()` with binary format
2. Test round-trip:

```
// Test: Save and load preserves index
cache1 = ZirCache.init()
cache1.load(".cache")  // Start fresh or load existing
cache1.put("main.mini", 0xabc123, "ir content")
cache1.put("lib.mini", 0xdef456, "lib content")
cache1.save()

// New process starts
cache2 = ZirCache.init()
cache2.load(".cache")

assert cache2.hasMatchingHash("main.mini", 0xabc123) == true
assert cache2.hasMatchingHash("lib.mini", 0xdef456) == true

// And we can still read the IR
ir = cache2.getLlvmIr("main.mini", 0xabc123)
assert ir == "ir content"
```

### Benchmark Data

| Operation | Time (10K entries) |
|-----------|--------------------|
| Save index | ~30ms |
| Load index | ~50ms |
| Index file size | ~200KB |

Compare to JSON:
| Format | Load Time | File Size |
|--------|-----------|-----------|
| JSON | ~500ms | ~800KB |
| Binary | ~50ms | ~200KB |
| **Speedup** | **10x** | **4x smaller** |

---

## Summary: Complete ZirCache

```
┌────────────────────────────────────────────────────────────────────┐
│ ZirCache - Complete Implementation                                 │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ ZirCache {                                                         │
│     cache_dir: string                                              │
│     index: Map<path, u64>     // Fast lookup                       │
│ }                                                                  │
│                                                                    │
│ Methods:                                                           │
│     init()                    // Create empty cache                │
│     load(cache_dir)           // Load index from disk              │
│     save()                    // Save index to disk                │
│     hasMatchingHash(path, hash) -> bool  // Fast check             │
│     put(path, hash, ir)       // Store IR                          │
│     getLlvmIr(path, hash) -> string | null  // Retrieve IR         │
│                                                                    │
│ Storage:                                                           │
│     .cache/                                                        │
│     ├── zir_index.bin         // Binary index                      │
│     └── zir/                  // Git-style object storage          │
│         ├── 3d/                                                    │
│         │   └── b3b7314a73226b                                     │
│         └── ...                                                    │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Performance Summary:**

| Feature | Impact |
|---------|--------|
| Content-addressed storage | Deduplication, no memory pressure |
| Git-style directories | Fast filesystem operations |
| In-memory index | 100x faster cache checks |
| Binary persistence | 10x faster startup |

---

## Next Steps

You can now cache entire files. But what if only one function in a file changed? Do we really need to recompile ALL functions?

**Next: [Module 3: Function-Level Cache](../03-function-cache/)** - Cache individual functions

---

## Complete Code Reference

For a complete implementation, see:
- `src/cache.zig` - `ZirCache` struct and methods

Key functions:
- `getObjectPath()` - Hash to Git-style path
- `putObject()` / `getObject()` - Content-addressed storage
- `ZirCache.save()` / `load()` - Binary persistence
- `ZirCache.hasMatchingHash()` - Fast lookup
