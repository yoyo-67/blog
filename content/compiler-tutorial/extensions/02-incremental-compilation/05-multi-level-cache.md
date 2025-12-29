---
title: "2.5: Multi-Level Cache"
weight: 5
---

# Lesson 2.5: Multi-Level Cache

Let's combine everything into a complete incremental compilation system.

---

## Goal

Build a multi-level cache that combines:
- File-level caching (skip unchanged files entirely)
- Function-level caching (reuse unchanged functions within changed files)

---

## Multi-Level Cache Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         MULTI-LEVEL CACHE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  LEVEL 1: FILE CACHE                                                │   │
│   │  "Has this file changed at all?"                                    │   │
│   │  - Check mtime                                                      │   │
│   │  - Check dependencies                                               │   │
│   │  - If unchanged: skip to cached LLVM IR                             │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼ (file changed)                          │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  LEVEL 2: ZIR CACHE (optional)                                      │   │
│   │  "Have we parsed this file before?"                                 │   │
│   │  - Cache parsed ZIR per file                                        │   │
│   │  - Skip lexing/parsing if source unchanged                          │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼ (need to compile)                       │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  LEVEL 3: AIR CACHE (per-function)                                  │   │
│   │  "Has this specific function changed?"                              │   │
│   │  - Hash function's ZIR                                              │   │
│   │  - If unchanged: use cached LLVM IR for just this function          │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## MultiLevelCache Structure

```
MultiLevelCache = struct {
    allocator:   Allocator,
    cache_dir:   string,
    file_cache:  Cache,       // File-level (from lesson 3)
    zir_cache:   ZirCache,    // Optional: parsed ZIR per file
    air_cache:   AirCache,    // Per-function (from lesson 4)
}

ZirCache = struct {
    entries: Map<string, ZirCacheEntry>,
}

ZirCacheEntry = struct {
    path:           string,
    source_hash:    u64,
    function_names: []string,  // Functions in this file
}
```

---

## Step 1: Initialize Multi-Level Cache

```
MultiLevelCache.init(allocator, cache_dir) -> MultiLevelCache {
    return MultiLevelCache {
        allocator: allocator,
        cache_dir: cache_dir,
        file_cache: Cache.init(allocator, cache_dir),
        zir_cache: ZirCache.init(allocator),
        air_cache: AirCache.init(allocator, cache_dir),
    }
}
```

---

## Step 2: Load All Caches

```
MultiLevelCache.load(self) {
    self.file_cache.load()
    self.air_cache.load()
    // ZIR cache is memory-only (rebuilt each session)
}
```

---

## Step 3: Save All Caches

```
MultiLevelCache.save(self) {
    self.file_cache.save()
    self.air_cache.save()
}
```

---

## Step 4: Compile with Cache

The main compilation function using all cache levels:

```
compileWithCache(allocator, path, cache) -> CompileResult {
    // LEVEL 1: Check file cache
    if not cache.file_cache.needsRecompile(path) {
        // File unchanged - use fully cached output
        if cached_ir = cache.file_cache.getCachedLLVMIR(path) {
            return CompileResult {
                llvm_ir: cached_ir,
                from_cache: true,
            }
        }
    }

    // File changed - need to recompile (but can still use function cache)

    // Parse the file
    source = read_file(path)
    unit = CompilationUnit.init(allocator, path)
    unit.load(arena)
    unit.loadImports(arena, units)

    // Generate program
    program = unit.generateProgram(allocator)

    // LEVEL 3: Use per-function cache during codegen
    cached_gen = CachedCodegen.init(allocator, cache.air_cache, path)
    llvm_ir = cached_gen.generate(program)

    // Update file cache
    deps = collectDependencies(unit)
    cache.file_cache.update(path, llvm_ir, deps)

    return CompileResult {
        llvm_ir: llvm_ir,
        functions_cached: cached_gen.stats.functions_cached,
        functions_compiled: cached_gen.stats.functions_compiled,
    }
}

CompileResult = struct {
    llvm_ir:            string,
    functions_cached:   usize,
    functions_compiled: usize,
}
```

---

## Step 5: Incremental Build Command

Add a build command that uses caching:

```
incrementalBuild(allocator, path, verbose) {
    // Initialize cache
    cache = MultiLevelCache.init(allocator, ".mini_cache")
    cache.load()

    if verbose {
        print("[cache] Loaded {} functions", cache.air_cache.count())
    }

    // Compile with cache
    result = compileWithCache(allocator, path, cache)

    // Save cache for next run
    cache.save()

    if verbose {
        print("[build] Functions: {} cached, {} compiled",
            result.functions_cached,
            result.functions_compiled)
    }

    // Write output
    output_path = replace(path, ".mini", ".ll")
    write_file(output_path, result.llvm_ir)

    print("[build] Output: {}", output_path)
}
```

---

## Complete Flow Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         INCREMENTAL BUILD FLOW                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   $ comp build main.mini -v                                                  │
│                                                                              │
│   [cache] Loaded AIR cache with 5 functions                                  │
│                                                                              │
│   Checking main.mini:                                                        │
│   ├── mtime changed? YES                                                     │
│   ├── Parsing...                                                             │
│   ├── Function main(): hash=0x123, cached? NO → compile                      │
│   └── Done                                                                   │
│                                                                              │
│   Checking math.mini (import):                                               │
│   ├── mtime changed? NO                                                      │
│   └── Using fully cached output                                              │
│                                                                              │
│   [build] Functions: 3 cached, 1 compiled                                    │
│   [build] Output: main.ll                                                    │
│                                                                              │
│   Second run (no changes):                                                   │
│   [cache] Loaded AIR cache with 6 functions                                  │
│   [build] No changes, using cache                                            │
│   [build] Output (cached): main.ll                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Cache Statistics

Track and report cache performance:

```
CacheStats = struct {
    file_entries:    usize,
    air_entries:     usize,
    cache_hits:      usize,
    cache_misses:    usize,
}

MultiLevelCache.getStats(self) -> CacheStats {
    return CacheStats {
        file_entries: self.file_cache.entries.count(),
        air_entries: self.air_cache.entries.count(),
    }
}
```

---

## Verify Your Implementation

### Test 1: First build (cold cache)
```
$ rm -rf .mini_cache
$ comp build main.mini -v

Expected:
  [cache] Loaded AIR cache with 0 functions
  [build] Functions: 0 cached, 3 compiled
  [build] Output: main.ll
```

### Test 2: Second build (warm cache, no changes)
```
$ comp build main.mini -v

Expected:
  [cache] Loaded AIR cache with 3 functions
  [build] No changes, using cache
  [build] Output (cached): main.ll
```

### Test 3: Build after modifying one function
```
# Edit main.mini, change only main()
$ comp build main.mini -v

Expected:
  [build] Functions: 2 cached, 1 compiled
  (imported functions still cached)
```

---

## Summary

You've built a complete incremental compilation system:

1. **File hashing** - Detect when files change
2. **File cache** - Skip unchanged files entirely
3. **Function cache** - Reuse unchanged functions
4. **Multi-level cache** - Combine for maximum efficiency

This same architecture is used by production compilers like Rust, Go, and TypeScript!

---

## What's Next

Congratulations! You've completed the compiler extensions.

Ideas for further exploration:
- **Parallel compilation** - Compile independent files simultaneously
- **Watch mode** - Automatically rebuild when files change
- **Distributed caching** - Share cache across machines
- **Profile-guided optimization** - Cache based on runtime data

Back to: [Extensions Overview](../../) →
