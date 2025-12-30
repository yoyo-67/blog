---
title: "Module 4: Multi-Level Integration"
weight: 4
---

# Module 4: Multi-Level Cache Integration

You have three caches. Now let's combine them into a unified system that loads, saves, and operates efficiently.

**What you'll build:**
- A `MultiLevelCache` struct combining all caches
- Unified load/save operations
- A "fast path" that skips all work when nothing changed

---

## Sub-lesson 4.1: Cache Hierarchy

### The Problem

We have three independent caches:
- `FileHashCache` - Tracks file changes
- `ZirCache` - Stores file-level IR
- `AirCache` - Stores function-level IR

Managing them separately is error-prone:
```
// Scattered cache handling
hash_cache = FileHashCache.init()
zir_cache = ZirCache.init()
air_cache = AirCache.init()

hash_cache.load(cache_dir)
zir_cache.load(cache_dir)
air_cache.load()  // Forgot cache_dir!

// ... compile ...

hash_cache.save(cache_dir)
// Forgot to save zir_cache!
air_cache.save()
```

### The Solution

Wrap all caches in a single `MultiLevelCache` struct that manages them together.

```
┌─────────────────────────────────────────────────────────────────────┐
│ MULTI-LEVEL CACHE HIERARCHY                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ MultiLevelCache                                                     │
│ ├── cache_dir: ".cache"                                             │
│ ├── hash_cache: FileHashCache   ← Change detection                  │
│ ├── zir_cache: ZirCache         ← File-level IR                     │
│ └── air_cache: AirCache         ← Function-level IR                 │
│                                                                     │
│ One struct to:                                                      │
│   - Initialize all caches                                           │
│   - Load all caches                                                 │
│   - Save all caches                                                 │
│   - Provide coordinated access                                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Data Structure:**

```
MultiLevelCache {
    cache_dir: string
    hash_cache: FileHashCache    // mtime, content hash, imports
    zir_cache: ZirCache          // file → combined_hash → IR
    air_cache: AirCache          // function → zir_hash → IR
}
```

**Initialization:**

```
MultiLevelCache.init(cache_dir) -> MultiLevelCache {
    return MultiLevelCache {
        cache_dir: cache_dir,
        hash_cache: FileHashCache.init(),
        zir_cache: ZirCache.init(),
        air_cache: AirCache.init(cache_dir),
    }
}

MultiLevelCache.deinit(self) {
    self.hash_cache.deinit()
    self.zir_cache.deinit()
    self.air_cache.deinit()
}
```

### How the Caches Work Together

```
┌─────────────────────────────────────────────────────────────────────┐
│ BUILD REQUEST FOR main.mini                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ 1. FileHashCache: Has anything changed?                             │
│    ├── Check mtime for main.mini        → same? use cached hash     │
│    ├── Check mtime for math.mini        → same? use cached hash     │
│    ├── Check mtime for utils.mini       → CHANGED! recompute hash   │
│    └── Compute combined_hash for main.mini                          │
│                                                                     │
│ 2. ZirCache: Is main.mini's IR cached for this combined_hash?       │
│    ├── YES (combined_hash matches) → return cached IR, done!        │
│    └── NO (hash differs) → need to compile something                │
│                                                                     │
│ 3. AirCache: Which functions need recompilation?                    │
│    ├── main(): ZIR hash unchanged → use cached function IR          │
│    ├── helper(): ZIR hash unchanged → use cached function IR        │
│    └── process(): ZIR hash CHANGED → compile this function          │
│                                                                     │
│ Result: Only recompile what actually changed!                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Create `MultiLevelCache` struct
2. Implement `init()` and `deinit()`
3. Test:

```
// Test: All caches initialized
cache = MultiLevelCache.init(".cache")

assert cache.cache_dir == ".cache"
assert cache.hash_cache != null
assert cache.zir_cache != null
assert cache.air_cache != null

cache.deinit()  // No leaks!
```

---

## Sub-lesson 4.2: Unified Load/Save

### The Problem

Each cache needs to load from and save to disk. Doing this manually is tedious and error-prone:

```
// Easy to forget one!
hash_cache.load()
zir_cache.load()
// Forgot air_cache!

// Or save in wrong order
air_cache.save()
// Crash before saving hash_cache = stale cache on next run
```

### The Solution

Unified `load()` and `save()` methods that handle all caches atomically.

**Load All Caches:**

```
MultiLevelCache.load(self) {
    // Load file hash cache (mtime + hash + imports)
    self.hash_cache.load(self.cache_dir)

    // Load ZIR cache index
    self.zir_cache.load(self.cache_dir)

    // Load AIR cache (counts objects)
    self.air_cache.load()
}
```

**Save All Caches:**

```
MultiLevelCache.save(self) {
    // Save file hash cache
    self.hash_cache.save(self.cache_dir)

    // Save ZIR cache index
    self.zir_cache.save(self.cache_dir)

    // Save AIR cache (objects already on disk, just index)
    self.air_cache.save()
}
```

**Usage:**

```
// In your build function:
main() {
    cache = MultiLevelCache.init(".mini_cache")

    // Load all caches at startup
    cache.load()

    // ... do compilation ...

    // Save all caches at end
    cache.save()

    cache.deinit()
}
```

### Directory Structure

```
.mini_cache/
├── file_hashes.bin      # FileHashCache
├── zir_index.bin        # ZirCache index
├── zir/                 # ZirCache objects
│   ├── 3d/
│   │   └── b3b7314a73226b
│   └── ...
├── objects/             # AirCache objects
│   ├── aa/
│   │   └── 1234567890abcdef
│   └── ...
└── combined/            # For surgical patching (Module 5)
    └── main.mini.ll
```

### Stats for Debugging

Add stats to help debug cache behavior:

```
MultiLevelCache.printStats(self) {
    print("[cache] FileHashCache: {} entries", self.hash_cache.count())
    print("[cache] ZirCache: {} files indexed", self.zir_cache.index.count())
    print("[cache] AirCache: {} functions cached", self.air_cache.count())

    // FileHashCache detailed stats
    self.hash_cache.printStats()
    // Output: [hash-stats] stat: 1000 calls (50ms), read: 5 files (10ms), hits: 995
}
```

### Try It Yourself

1. Implement `load()` and `save()` methods
2. Test persistence:

```
// Test: Round-trip persistence
cache1 = MultiLevelCache.init(".cache")
cache1.hash_cache.ensureCached("test.mini")
cache1.zir_cache.put("test.mini", 0x123, "test ir")
cache1.save()

cache2 = MultiLevelCache.init(".cache")
cache2.load()

assert cache2.hash_cache.entries.count() == 1
assert cache2.zir_cache.hasMatchingHash("test.mini", 0x123)
```

### Clean Command

Add a method to clear all caches:

```
MultiLevelCache.clean(self) {
    deleteDirectory(self.cache_dir)
    print("[clean] Cache cleared: {}", self.cache_dir)
}
```

---

## Sub-lesson 4.3: Fast Path

### The Problem

Even checking the cache has overhead:
1. Load all cache indices (~50ms for 10K files)
2. Compute combined hash for entry file (~5ms with mtime)
3. Check ZirCache (~0.001ms)

For 10K files that haven't changed, steps 1-2 dominate. Can we do better?

### The Solution

Add a **fast path**: store a single hash of the ENTIRE project state. If it matches, nothing changed - skip everything.

```
┌─────────────────────────────────────────────────────────────────────┐
│ FAST PATH: "Nothing Changed" Check                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Store: project_hash = hash of entry file's combined_hash            │
│        (which includes ALL transitive dependencies)                 │
│                                                                     │
│ On build:                                                           │
│   1. Compute combined_hash for entry file                           │
│   2. Compare with stored project_hash                               │
│   3. If matches:                                                    │
│      → FAST PATH: Return cached output immediately                  │
│      → Skip: file enumeration, hash checking, compilation           │
│   4. If differs:                                                    │
│      → SLOW PATH: Normal incremental build                          │
│                                                                     │
│ Speedup: ~166x for "nothing changed" scenario (10s → 60ms)          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
incrementalBuild(cache, entry_path, base_dir, verbose) -> string {
    // Compute combined hash for entry file
    // (This already uses mtime optimization from FileHashCache)
    combined_hash = computeCombinedHash(
        cache.hash_cache,
        entry_path,
        base_dir
    )

    // FAST PATH: Check if we have this exact project state cached
    if cache.zir_cache.hasMatchingHash(entry_path, combined_hash) {
        // Combined hash matches! Check for cached combined IR
        if cache.zir_cache.getCombinedIr(entry_path) -> cached_output {
            if verbose {
                print("[fast-path] Nothing changed, using cached output")
            }
            return cached_output
        }
    }

    // SLOW PATH: Something changed, do incremental build
    if verbose {
        print("[build] Changes detected, rebuilding...")
    }

    output = doIncrementalBuild(cache, entry_path, combined_hash, verbose)

    // Store for fast path next time
    cache.zir_cache.put(entry_path, combined_hash, null)  // Update index
    cache.zir_cache.putCombinedIr(entry_path, output)     // Store output

    return output
}
```

**The Key Insight:**

```
combined_hash = hash(entry_file + ALL transitive imports)

If combined_hash is unchanged:
   → No file in the entire dependency tree changed
   → Cached output is valid
   → Return immediately!

This check costs:
   - 10K stat() calls (mtime checks): ~300ms
   - Hash comparison: ~0.001ms
   - Total: ~300ms

Without fast path (enumerate + compile):
   - 10K file reads: ~2500ms
   - Hash computation: ~500ms
   - Total: ~3000ms

Fast path speedup: 10x for "nothing changed"
```

### Complete Build Flow

```
incrementalBuild(cache, entry_path):

    ┌──────────────────────────────────────────────────────────────┐
    │ 1. Compute combined_hash                                     │
    │    └── Uses mtime cache (FileHashCache)                      │
    │    └── Only reads files with changed mtime                   │
    └──────────────────────────────────────────────────────────────┘
                                │
                                ▼
    ┌──────────────────────────────────────────────────────────────┐
    │ 2. Check fast path                                           │
    │    └── combined_hash matches cached?                         │
    │    └── YES → return cached output immediately                │
    └──────────────────────────────────────────────────────────────┘
                                │ NO
                                ▼
    ┌──────────────────────────────────────────────────────────────┐
    │ 3. Try surgical patching (Module 5)                          │
    │    └── Parse cached output for file markers                  │
    │    └── Recompile only changed files                          │
    │    └── Reassemble output                                     │
    └──────────────────────────────────────────────────────────────┘
                                │ (if no cached output)
                                ▼
    ┌──────────────────────────────────────────────────────────────┐
    │ 4. Full compilation with function caching                    │
    │    └── For each file: use ZirCache or compile                │
    │    └── For each function: use AirCache or compile            │
    │    └── Combine results with file markers                     │
    └──────────────────────────────────────────────────────────────┘
                                │
                                ▼
    ┌──────────────────────────────────────────────────────────────┐
    │ 5. Update caches                                             │
    │    └── Store new combined_hash → output mapping              │
    │    └── Store combined output for surgical patching           │
    └──────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Implement the fast path check in your build function
2. Test:

```
// Test: Fast path on second build
cache = MultiLevelCache.init(".cache")
cache.load()

// First build - slow path
output1 = incrementalBuild(cache, "main.mini", ".", verbose: true)
// Output: [build] Changes detected, rebuilding...

// Second build - fast path (no changes)
output2 = incrementalBuild(cache, "main.mini", ".", verbose: true)
// Output: [fast-path] Nothing changed, using cached output

assert output1 == output2

// Third build after touching a file
touch("utils.mini")
output3 = incrementalBuild(cache, "main.mini", ".", verbose: true)
// Output: [build] Changes detected, rebuilding...
```

### Benchmark Data

| Scenario | Without Fast Path | With Fast Path |
|----------|------------------|----------------|
| 10K files, none changed | ~1,250ms | ~300ms |
| 10K files, 1 changed | ~1,500ms | ~500ms |
| **Speedup** | - | **4x** |

The fast path is most impactful for the common case: running the build when nothing changed (e.g., after a failed test fix).

---

## Summary: Complete MultiLevelCache

```
┌────────────────────────────────────────────────────────────────────┐
│ MultiLevelCache - Complete Implementation                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ MultiLevelCache {                                                  │
│     cache_dir: string                                              │
│     hash_cache: FileHashCache                                      │
│     zir_cache: ZirCache                                            │
│     air_cache: AirCache                                            │
│ }                                                                  │
│                                                                    │
│ Methods:                                                           │
│     init(cache_dir)                                                │
│     deinit()                                                       │
│     load()              // Load all caches                         │
│     save()              // Save all caches                         │
│     clean()             // Delete cache directory                  │
│     printStats()        // Debug output                            │
│                                                                    │
│ incrementalBuild(cache, entry_path, base_dir, verbose):            │
│     1. Compute combined_hash (mtime-optimized)                     │
│     2. Fast path: combined_hash matches? Return cached output      │
│     3. Surgical patch: Recompile only changed files                │
│     4. Full build: Use function cache for compilation              │
│     5. Update caches                                               │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Performance Summary:**

| Scenario | Time (10K files) |
|----------|-----------------|
| Cold build | ~8s |
| Warm build (fast path) | ~300ms |
| 1 file changed | ~500ms |
| **Speedup (warm)** | **26x** |

---

## Next Steps

The fast path handles "nothing changed." But when something DOES change, we're still recompiling ALL files. Can we do better?

Yes! **Surgical patching** lets us recompile only the changed files and patch them into the cached output.

**Next: [Module 5: Surgical Patching](../05-surgical-patching/)** - Recompile only what changed

---

## Complete Code Reference

For a complete implementation, see:
- `src/cache.zig` - `MultiLevelCache` struct
- `src/main.zig` - `incrementalBuild()` function

Key patterns:
- Unified initialization and cleanup
- Sequential load/save for consistency
- Fast path with combined hash
