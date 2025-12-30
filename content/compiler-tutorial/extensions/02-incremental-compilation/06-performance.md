---
title: "Module 6: Performance"
weight: 6
---

# Module 6: Performance Optimization

Your incremental compiler works! But at 10K+ files, small inefficiencies compound. This module teaches you how to identify and eliminate bottlenecks.

**What you'll learn:**
- Avoiding redundant dependency traversals
- Minimizing memory allocations
- Measuring to find the real bottlenecks

---

## Sub-lesson 6.1: Avoid Redundant Visits

### The Problem

In a dependency tree, shared dependencies get visited multiple times:

```
Dependency tree:
    main.mini
    ├── math.mini
    │   └── utils.mini
    └── io.mini
        └── utils.mini   ← SAME FILE!

Naive traversal visits utils.mini TWICE.
With 10K files and deep dependencies, this explodes.
```

**Real-World Impact:**

```
10K files with ~3 imports each
Average depth: 14 levels
Naive visits: 10K × 2^14 = 163 MILLION visits!
With visited set: 10K visits

Speedup: 16,000x
```

### The Solution

Track visited files in a set. Skip files you've already processed.

**Before (Naive):**

```
traverseDependencies(cache, path, base_dir) {
    entry = cache.ensureCached(resolvePath(base_dir, path))

    for import_path in entry.imports {
        resolved = resolvePath(dirname(path), import_path)
        traverseDependencies(cache, resolved, base_dir)  // May revisit!
    }
}
```

**After (With Visited Set):**

```
traverseDependencies(cache, path, base_dir, visited) {
    // Skip if already visited
    if visited.contains(path) {
        return
    }
    visited.add(path)

    entry = cache.ensureCached(resolvePath(base_dir, path))

    for import_path in entry.imports {
        resolved = resolvePath(dirname(path), import_path)
        traverseDependencies(cache, resolved, base_dir, visited)
    }
}

// Usage
visited = Set<string>{}
traverseDependencies(cache, "main.mini", ".", visited)
```

**For Combined Hash Computation:**

```
computeCombinedHashWithVisited(cache, path, base_dir) -> u64 {
    hasher = Hasher.init()
    visited = Set<string>{}

    addToHashRecursive(cache, path, base_dir, hasher, visited)

    return hasher.final()
}

addToHashRecursive(cache, path, base_dir, hasher, visited) {
    if visited.contains(path) {
        return  // Already hashed this file
    }
    visited.add(path)

    full_path = resolvePath(base_dir, path)
    entry = cache.ensureCached(full_path)

    // Hash this file's content
    hasher.update(to_bytes(entry.hash))

    // Recursively hash imports
    for import_path in entry.imports {
        resolved = resolvePath(dirname(path), import_path)
        addToHashRecursive(cache, resolved, base_dir, hasher, visited)
    }
}
```

### Try It Yourself

1. Add a `visited` parameter to your traversal functions
2. Test:

```
// Test: Same dependency visited once
counter = 0
visited = Set<string>{}

traverseWithCounter(path, visited) {
    if visited.contains(path) return
    visited.add(path)
    counter += 1
    // ... traverse imports
}

// Diamond dependency: A → B, C; B → D; C → D
// D should only be counted once
traverseWithCounter("A", visited)
assert counter == 4  // A, B, C, D (not A, B, D, C, D)
```

### Benchmark Data

| Scenario | Without Visited | With Visited | Speedup |
|----------|----------------|--------------|---------|
| 1K files, 3 imports avg | 500ms | 50ms | **10x** |
| 10K files, 3 imports avg | timeout | 300ms | **∞** |

---

## Sub-lesson 6.2: Minimize Allocations

### The Problem

Path resolution creates lots of temporary strings:

```
resolvePath("files/file_00001.mini", "file_00002.mini")
// Creates new string: "files/file_00002.mini"

With 10K files traversed multiple times:
- 50K+ path resolutions
- 50K+ string allocations
- ~720ms just in allocation overhead!
```

### The Solution

Use stack-allocated buffers instead of heap allocations.

**Before (Heap Allocation):**

```
resolvePath(base, relative) -> string {
    if isAbsolute(relative) {
        return copy(relative)  // Allocation!
    }

    dir = dirname(base)        // Allocation!
    return join(dir, relative) // Allocation!
}
```

**After (Stack Buffer):**

```
resolvePathStack(base, relative, buffer) -> slice {
    // Write directly into provided buffer
    if isAbsolute(relative) {
        copy(buffer, relative)
        return buffer[0..relative.len]
    }

    // Find directory end
    dir_end = 0
    for i, c in base {
        if c == '/' {
            dir_end = i + 1
        }
    }

    // Copy directory part
    copy(buffer[0..dir_end], base[0..dir_end])

    // Copy relative part
    copy(buffer[dir_end..], relative)

    return buffer[0..dir_end + relative.len]
}

// Usage
var buffer: [1024]u8 = undefined
resolved = resolvePathStack(base, relative, &buffer)
```

**In Traversal:**

```
traverseDependencies(cache, path, base_dir, visited) {
    if visited.contains(path) return
    visited.add(path)

    // Stack buffer for path resolution
    var path_buffer: [1024]u8 = undefined

    full_path = resolvePathStack(base_dir, path, &path_buffer)
    entry = cache.ensureCached(full_path)

    for import_path in entry.imports {
        var import_buffer: [1024]u8 = undefined
        resolved = resolvePathStack(dirname(path), import_path, &import_buffer)

        traverseDependencies(cache, resolved, base_dir, visited)
    }
}
```

### Why This Works

```
┌─────────────────────────────────────────────────────────────────────┐
│ HEAP vs STACK ALLOCATION                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ HEAP (allocator.alloc):                                             │
│   - Lock allocator mutex                                            │
│   - Find free block                                                 │
│   - Update bookkeeping                                              │
│   - Return pointer                                                  │
│   - Later: free, coalesce blocks                                    │
│   Cost: ~100-1000 ns per allocation                                 │
│                                                                     │
│ STACK (local buffer):                                               │
│   - Already allocated on function entry                             │
│   - Just use it                                                     │
│   - Freed automatically on return                                   │
│   Cost: ~0 ns (already there)                                       │
│                                                                     │
│ 50K allocations × 100ns = 5ms (heap)                                │
│ 50K allocations × 0ns = 0ms (stack)                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Other Allocation Hotspots

Common places to optimize:

| Location | Before | After |
|----------|--------|-------|
| Path resolution | `allocPrint()` | Stack buffer |
| Hash hex strings | `format("{x}")` | Fixed buffer |
| String building | ArrayList | Pre-sized buffer |
| Temporary arrays | `allocator.alloc()` | Stack arrays |

### Try It Yourself

1. Identify allocation hotspots in your traversal
2. Replace with stack buffers
3. Measure:

```
// Benchmark
timer = startTimer()

for _ in 0..10000 {
    resolved = resolvePath(base, relative)  // Before
}

heap_time = timer.elapsed()

timer.reset()

var buffer: [1024]u8 = undefined
for _ in 0..10000 {
    resolved = resolvePathStack(base, relative, &buffer)  // After
}

stack_time = timer.elapsed()

print("Heap: {}ms, Stack: {}ms, Speedup: {}x",
    heap_time, stack_time, heap_time / stack_time)
// Typical output: Heap: 50ms, Stack: 2ms, Speedup: 25x
```

### Benchmark Data

| Operation | Heap Alloc | Stack Buffer | Speedup |
|-----------|-----------|--------------|---------|
| Path resolution (50K calls) | 720ms | 3ms | **240x** |
| Hash formatting | 100ms | 5ms | **20x** |
| Total build (10K files) | 2.5s | 1.8s | **1.4x** |

---

## Sub-lesson 6.3: Measure Everything

### The Problem

You optimized something, but the build is still slow. Where's the time going?

```
"It feels slow" - not actionable
"Hash computation takes 2.5s out of 8s total" - actionable!
```

### The Solution

Add timing stats to every significant operation.

**Stats Structure:**

```
BuildStats {
    // Phase timings (nanoseconds)
    cache_load_ns: i64
    hash_compute_ns: i64
    compile_ns: i64
    surgical_patch_ns: i64
    cache_save_ns: i64

    // Counts
    files_total: usize
    files_cached: usize
    files_compiled: usize
    functions_total: usize
    functions_cached: usize
    functions_compiled: usize

    // Sub-timings for hash computation
    stat_calls: usize
    stat_time_ns: i64
    read_count: usize
    read_time_ns: i64
    hash_time_ns: i64
}
```

**Instrument Your Code:**

```
incrementalBuild(cache, entry_path) -> (string, BuildStats) {
    stats = BuildStats.init()

    // Time cache load
    start = nanoTimestamp()
    cache.load()
    stats.cache_load_ns = nanoTimestamp() - start

    // Time hash computation
    start = nanoTimestamp()
    combined_hash = computeCombinedHash(cache.hash_cache, entry_path)
    stats.hash_compute_ns = nanoTimestamp() - start

    // Copy sub-stats from hash cache
    stats.stat_calls = cache.hash_cache.stat_count
    stats.stat_time_ns = cache.hash_cache.stat_time_ns
    stats.read_count = cache.hash_cache.read_count
    stats.read_time_ns = cache.hash_cache.read_time_ns

    // Time compilation
    start = nanoTimestamp()
    output = compile(...)
    stats.compile_ns = nanoTimestamp() - start

    // Time cache save
    start = nanoTimestamp()
    cache.save()
    stats.cache_save_ns = nanoTimestamp() - start

    return (output, stats)
}
```

**Pretty Print Stats:**

```
BuildStats.print(self) {
    total_ms = (self.cache_load_ns + self.hash_compute_ns +
                self.compile_ns + self.cache_save_ns) / 1_000_000

    print("=== Build Stats ===")
    print("Total: {}ms", total_ms)
    print("")
    print("Phases:")
    print("  Cache load:    {}ms", self.cache_load_ns / 1_000_000)
    print("  Hash compute:  {}ms", self.hash_compute_ns / 1_000_000)
    print("    - stat():    {} calls, {}ms",
          self.stat_calls, self.stat_time_ns / 1_000_000)
    print("    - read():    {} files, {}ms",
          self.read_count, self.read_time_ns / 1_000_000)
    print("    - hash():    {}ms", self.hash_time_ns / 1_000_000)
    print("  Compile:       {}ms", self.compile_ns / 1_000_000)
    print("  Cache save:    {}ms", self.cache_save_ns / 1_000_000)
    print("")
    print("Files: {} total, {} cached, {} compiled",
          self.files_total, self.files_cached, self.files_compiled)
    print("Functions: {} total, {} cached, {} compiled",
          self.functions_total, self.functions_cached, self.functions_compiled)
}
```

**Example Output:**

```
=== Build Stats ===
Total: 1250ms

Phases:
  Cache load:    390ms
  Hash compute:  847ms
    - stat():    10001 calls, 300ms
    - read():    5 files, 47ms
    - hash():    500ms
  Compile:       0ms
  Cache save:    13ms

Files: 10001 total, 10001 cached, 0 compiled
Functions: 30003 total, 30003 cached, 0 compiled
```

**What This Tells You:**

```
From the stats above:
1. Hash compute is the bottleneck (847ms of 1250ms = 68%)
2. Most time in hash is stat() calls (300ms)
3. Actual hashing is fast (500ms for 10K cached entries)
4. Only 5 files were actually read (mtime optimization working!)

Next optimization targets:
- Can we parallelize stat() calls? (currently sequential)
- Can we batch stat() calls? (one syscall for multiple files)
- Can we cache stat() results across builds?
```

### Finding Bottlenecks

| What Stats Show | Possible Optimization |
|-----------------|----------------------|
| stat() time high | Parallel stat, file watching |
| read() time high | Memory-mapped files, read caching |
| hash() time high | Faster hash algorithm, incremental hash |
| compile time high | Parallel compilation, better IR |
| cache load high | Binary format, memory mapping |

### Try It Yourself

1. Add `BuildStats` struct
2. Instrument your build function
3. Run and analyze:

```
// Cold build
$ rm -rf .cache
$ comp build main.mini --stats
=== Build Stats ===
Total: 7970ms
  Cache load:    0ms
  Hash compute:  2555ms
  Compile:       5273ms
  Cache save:    142ms

// Warm build
$ comp build main.mini --stats
=== Build Stats ===
Total: 1250ms
  Cache load:    390ms
  Hash compute:  847ms
  Compile:       0ms
  Cache save:    13ms

// Incremental build (1 file changed)
$ touch files/file_00500.mini
$ comp build main.mini --stats
=== Build Stats ===
Total: 1810ms
  Cache load:    393ms
  Hash compute:  938ms
  Compile:       337ms
  Cache save:    142ms
```

### Benchmark Data: Real 10K File Project

| Scenario | Time | Breakdown |
|----------|------|-----------|
| Cold build | 7.97s | Hash: 2.5s, Compile: 5.3s, Save: 0.1s |
| Warm build | 1.25s | Load: 0.4s, Hash: 0.8s |
| 1 file changed | 1.81s | Load: 0.4s, Hash: 0.9s, Patch: 0.3s, Save: 0.1s |

---

## Summary: Performance Optimization

```
┌────────────────────────────────────────────────────────────────────┐
│ OPTIMIZATION SUMMARY                                               │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ TECHNIQUE           │ BEFORE    │ AFTER     │ SPEEDUP              │
│ ────────────────────┼───────────┼───────────┼──────────            │
│ Visited set         │ timeout   │ 300ms     │ ∞                    │
│ Stack buffers       │ 720ms     │ 3ms       │ 240x                 │
│ Binary cache format │ 500ms     │ 50ms      │ 10x                  │
│ mtime optimization  │ 2500ms    │ 300ms     │ 8x                   │
│                                                                    │
│ MEASURE FIRST!                                                     │
│ - Don't guess where time goes                                      │
│ - Add timing stats to find real bottlenecks                        │
│ - Optimize the biggest contributor first                           │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## What You've Built

Congratulations! You've built a complete incremental compilation system:

| Module | What You Built | Key Technique |
|--------|---------------|---------------|
| 1. Change Detection | FileHashCache | mtime + content hash |
| 2. File Cache | ZirCache | Git-style content-addressed storage |
| 3. Function Cache | AirCache + CachedCodegen | ZIR hashing |
| 4. Multi-Level | MultiLevelCache | Fast path with combined hash |
| 5. Surgical Patching | File markers + assembly | Partial rebuilds |
| 6. Performance | Stats + optimizations | Visited sets, stack buffers |

**Final Performance:**

| Scenario | Time (10K files) |
|----------|-----------------|
| Cold build | ~8s |
| Warm build (nothing changed) | ~1.2s |
| 1 file changed | ~1.8s |
| **Speedup vs naive** | **6-26x** |

---

## Ideas for Further Exploration

- **Parallel compilation** - Compile independent files simultaneously
- **Watch mode** - Rebuild automatically when files change
- **Distributed cache** - Share cache across machines (like ccache)
- **Cache compression** - Compress stored IR
- **Incremental linking** - Patch the final binary instead of relinking

---

## Complete Code Reference

For a complete implementation, see:
- `src/cache.zig` - All cache structures with timing stats
- `src/main.zig` - Build orchestration with stats printing

The same architecture powers production compilers:
- **Rust** - Incremental compilation since 2018
- **Go** - Build cache for package compilation
- **TypeScript** - Project references and incremental mode

You now understand how they work!

---

Back to: [Incremental Compilation Overview](../) →
