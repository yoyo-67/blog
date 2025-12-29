---
title: "2.6: Multi-Level Cache"
weight: 6
---

# Lesson 2.6: Multi-Level Cache

Let's combine everything into a complete incremental compilation system.

---

## Goal

Build a `MultiLevelCache` that combines:
- **FileHashCache** - Fast change detection with import tracking
- **ZirCache** - File-level LLVM IR cache
- **AirCache** - Function-level LLVM IR cache
- **Surgical Patching** - Partial output rebuilds

---

## MultiLevelCache Structure

```
MultiLevelCache {
    allocator:   Allocator,
    cache_dir:   string,
    hash_cache:  FileHashCache,   // Mtime + hash + imports
    zir_cache:   ZirCache,        // File-level LLVM IR
    air_cache:   AirCache,        // Function-level LLVM IR
}
```

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         MULTI-LEVEL CACHE ARCHITECTURE                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   BUILD REQUEST                                                              │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  FileHashCache                                                      │   │
│   │  - Check mtime for each file                                        │   │
│   │  - Compute combined hash (includes transitive imports)              │   │
│   │  - Track which files actually changed                               │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  ZirCache (File-Level)                                              │   │
│   │  - Check: hasMatchingHash(path, combined_hash)?                     │   │
│   │  - HIT: Return cached LLVM IR                                       │   │
│   │  - MISS: Continue to next level                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│        │                                                                     │
│        ▼ (cache miss)                                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  Surgical Patching                                                  │   │
│   │  - Parse cached combined IR for file sections                       │   │
│   │  - Identify changed vs unchanged files                              │   │
│   │  - If beneficial: patch only changed sections                       │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│        │                                                                     │
│        ▼ (need to compile)                                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  AirCache (Function-Level)                                          │   │
│   │  - For each function: check ZIR hash                                │   │
│   │  - HIT: Use cached function IR                                      │   │
│   │  - MISS: Compile function, cache result                             │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│        │                                                                     │
│        ▼                                                                     │
│   OUTPUT                                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Initialize Multi-Level Cache

```
MultiLevelCache.init(allocator, cache_dir) -> MultiLevelCache {
    return MultiLevelCache {
        allocator: allocator,
        cache_dir: cache_dir,
        hash_cache: FileHashCache.init(allocator),
        zir_cache: ZirCache.init(cache_dir),
        air_cache: AirCache.init(cache_dir),
    }
}
```

---

## Step 2: Load All Caches

```
MultiLevelCache.load(self) {
    // Load file hash cache (mtime, hash, imports)
    self.hash_cache.load(format("{}/file_hashes.bin", self.cache_dir))

    // Load ZIR cache index
    self.zir_cache.load()

    // Load AIR cache index
    self.air_cache.load()

    if verbose {
        print("[cache] Loaded: {} files (hash), {} files (ZIR), {} functions (AIR)",
            self.hash_cache.count(),
            self.zir_cache.loaded_count,
            self.air_cache.loaded_count)
    }
}
```

---

## Step 3: Save All Caches

```
MultiLevelCache.save(self) {
    self.hash_cache.save(format("{}/file_hashes.bin", self.cache_dir))
    self.zir_cache.save()
    self.air_cache.save()
}
```

---

## Step 4: Incremental Build with All Levels

```
incrementalBuild(allocator, files, cache, verbose) -> string {
    results = []

    for file in files {
        // Read source
        source = read_file(file.path)

        // Compute combined hash (using FileHashCache for mtime optimization)
        combined_hash = computeCombinedHashWithCache(
            cache.hash_cache,
            file.path,
            source
        )

        // LEVEL 1: Check ZirCache (file-level)
        if cache.zir_cache.hasMatchingHash(file.path, combined_hash) {
            cached_ir = cache.zir_cache.getLlvmIr(file.path, combined_hash)
            if cached_ir != null {
                if verbose {
                    print("[cache] HIT (file): {}", file.path)
                }
                results.append({ path: file.path, ir: cached_ir, from_cache: true })
                continue
            }
        }

        // LEVEL 2: Try surgical patching
        if cache.zir_cache.getCombinedIr(file.path) != null {
            patched = trySurgicalPatch(cache, file, combined_hash, verbose)
            if patched != null {
                results.append({ path: file.path, ir: patched, from_cache: false })
                continue
            }
        }

        // LEVEL 3: Compile with per-function caching
        if verbose {
            print("[compile] {}", file.path)
        }

        program = compile(source)
        cached_gen = CachedCodegen.init(allocator, cache.air_cache, file.path)
        llvm_ir = cached_gen.generate(program)

        if verbose {
            print("[cache] Functions: {} cached, {} compiled",
                cached_gen.stats.functions_cached,
                cached_gen.stats.functions_compiled)
        }

        // Update caches
        cache.zir_cache.put(file.path, combined_hash, llvm_ir)

        results.append({ path: file.path, ir: llvm_ir, from_cache: false })
    }

    // Combine all results with file markers
    output = generateWithMarkers(results)

    // Save combined IR for surgical patching
    cache.zir_cache.putCombinedIr("main", output)

    // Persist all caches
    cache.save()

    return output
}
```

---

## Step 5: Clean Command

```
MultiLevelCache.clean(self) {
    deleteDirectory(self.cache_dir)
    print("[clean] Cache cleared")
}
```

---

## Complete Build Flow Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         INCREMENTAL BUILD FLOW                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   $ comp build main.mini -v                                                  │
│                                                                              │
│   [cache] Loaded: 5 files (hash), 5 files (ZIR), 12 functions (AIR)         │
│                                                                              │
│   Processing main.mini:                                                      │
│   ├── combined_hash = 0x123... (computed with transitive deps)              │
│   ├── ZirCache: hasMatchingHash? NO (hash changed)                          │
│   ├── Surgical patch: 1/3 files changed                                     │
│   │   ├── main.mini: CHANGED → recompile                                    │
│   │   ├── math.mini: UNCHANGED → use cached section                         │
│   │   └── utils.mini: UNCHANGED → use cached section                        │
│   └── Compiling main.mini with AirCache:                                    │
│       ├── main(): hash=0xaaa, cached? NO → compile                          │
│       ├── helper(): hash=0xbbb, cached? YES → use cache                     │
│       └── Functions: 1 cached, 1 compiled                                   │
│                                                                              │
│   [build] Output: main.ll                                                    │
│   [build] Files: 2 cached, 1 compiled                                        │
│   [build] Functions: 1 cached, 1 compiled                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Cache Directory Structure

```
.mini_cache/
├── file_hashes.bin      # FileHashCache: path → (mtime, hash, imports)
├── zir_index.bin        # ZirCache index: path → combined_hash
├── zir/                 # ZirCache objects (Git-style)
│   ├── 3d/
│   │   └── b3b7314a73226b
│   └── 9a/
│       └── 2eb98b6d927e93
├── objects/             # AirCache objects (Git-style)
│   ├── aa/
│   │   └── a111222333444555
│   ├── bb/
│   │   └── b222333444555666
│   └── cc/
│       └── c333444555666777
└── combined/            # Combined IRs for surgical patching
    └── main.ll
```

---

## Performance Comparison

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         PERFORMANCE COMPARISON                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Scenario: 100 files, 1000 functions, 1 file changed                        │
│                                                                              │
│   NO CACHE:                                                                  │
│   ─────────                                                                  │
│   Compile: 100 files, 1000 functions                                         │
│   Time: 100 units                                                            │
│                                                                              │
│   FILE CACHE ONLY (ZirCache):                                                │
│   ───────────────────────────                                                │
│   Check: 100 file hashes                                                     │
│   Compile: 1 file (changed), ~10 functions                                   │
│   Time: 10 units (10x faster)                                                │
│                                                                              │
│   FILE + FUNCTION CACHE (ZirCache + AirCache):                               │
│   ─────────────────────────────────────────────                              │
│   Check: 100 file hashes, 10 function hashes                                 │
│   Compile: 1 function (actually changed)                                     │
│   Time: 1 unit (100x faster!)                                                │
│                                                                              │
│   FILE + FUNCTION + SURGICAL PATCH:                                          │
│   ─────────────────────────────────                                          │
│   Check: 100 file hashes                                                     │
│   Parse: cached combined IR                                                  │
│   Compile: 1 file                                                            │
│   Patch: replace 1 section                                                   │
│   Time: ~2 units (skip parsing unchanged files!)                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Implementation

### Test 1: Cold cache (first build)
```
$ rm -rf .mini_cache
$ comp build main.mini -v

Expected:
  [cache] Loaded: 0 files, 0 functions
  [compile] main.mini
  [compile] math.mini
  [build] Files: 0 cached, 3 compiled
```

### Test 2: Warm cache (no changes)
```
$ comp build main.mini -v

Expected:
  [cache] Loaded: 3 files, 10 functions
  [cache] HIT (file): main.mini
  [cache] HIT (file): math.mini
  [build] Files: 3 cached, 0 compiled
```

### Test 3: One file changed
```
# Modify math.mini
$ comp build main.mini -v

Expected:
  [cache] HIT (file): main.mini
  [compile] math.mini
  [cache] Functions: 2 cached, 1 compiled
  [build] Files: 2 cached, 1 compiled
```

### Test 4: Dependency changed
```
# Modify utils.mini (imported by math.mini, which is imported by main.mini)
$ comp build main.mini -v

Expected:
  Combined hash changed for ALL files (transitive dependency)
  Surgical patching kicks in
  [build] Surgical patch: 2/3 cached sections used
```

---

## Summary

You've built a complete incremental compilation system:

| Component | Purpose | Key Technique |
|-----------|---------|---------------|
| FileHashCache | Change detection | Mtime + content hash + imports |
| ZirCache | File-level cache | Git-style storage, combined hash |
| AirCache | Function-level cache | ZIR hashing |
| Surgical Patching | Partial rebuilds | File markers in output |

This same architecture is used by production compilers like Rust, Go, and TypeScript!

---

## Ideas for Further Exploration

- **Parallel compilation** - Compile independent files simultaneously
- **Watch mode** - Automatically rebuild when files change
- **Distributed caching** - Share cache across machines (like ccache)
- **Cache compression** - Compress stored LLVM IR
- **Cache eviction** - Remove old/unused entries

---

## What's Next

Congratulations! You've completed the incremental compilation section.

Back to: [Extensions Overview](../../) →
