---
title: "Module 1: File Change Detection"
weight: 1
---

# Module 1: File Change Detection (FileHashCache)

How do we know if a file needs recompilation? This module teaches you to build a `FileHashCache` that efficiently tracks file changes with mtime optimization.

**What you'll build:**
- Content hashing for reliable change detection
- mtime checking to skip unchanged files (10x faster)
- Import extraction for dependency tracking
- Binary persistence for fast loading
- Combined hashing for transitive dependencies

---

## Sub-lesson 1.1: Naive Content Hashing

### The Problem

Every time the compiler runs, it needs to know: "Has this file changed since last time?"

The naive approach: read every file and compute a hash. If the hash differs from the cached hash, the file changed.

```
NAIVE APPROACH:
For each file:
    1. Read entire file content
    2. Compute hash of content
    3. Compare with cached hash
    4. If different → file changed

Problem: 10,000 files × ~1KB each = 10MB of I/O EVERY build
         Even when NOTHING changed!
```

### The Solution

Start with the simplest working solution, then optimize later.

**Data Structures:**

```
FileHashEntry {
    hash: u64           // Content hash
}

FileHashCache {
    entries: Map<path, FileHashEntry>
}
```

**Hashing Function:**

Use a fast, non-cryptographic hash like [WyHash](https://github.com/wangyi-fudan/wyhash). We need:
- **Fast** - We hash on every build
- **Collision-resistant** - Different files should have different hashes
- **Deterministic** - Same content always produces same hash

We don't need cryptographic security.

```
hashSource(source: bytes) -> u64 {
    return wyhash(seed: 0, data: source)
}
```

**Cache Lookup:**

```
FileHashCache.getHash(self, path) -> u64 {
    // Check cache first
    if self.entries.get(path) -> entry {
        return entry.hash
    }

    // Not cached - read and hash
    source = read_file(path)
    hash = hashSource(source)

    self.entries.put(path, FileHashEntry{ hash: hash })
    return hash
}
```

### Try It Yourself

1. Implement `hashSource()` using WyHash (or your language's equivalent)
2. Create a simple `FileHashCache` with a Map
3. Test with these cases:

```
// Test 1: Same content → same hash
source1 = "fn main() { return 42; }"
source2 = "fn main() { return 42; }"
assert hashSource(source1) == hashSource(source2)

// Test 2: Different content → different hash
source1 = "fn main() { return 42; }"
source2 = "fn main() { return 43; }"
assert hashSource(source1) != hashSource(source2)

// Test 3: Cache returns consistent hashes
cache = FileHashCache.init()
hash1 = cache.getHash("test.mini")
hash2 = cache.getHash("test.mini")
assert hash1 == hash2
```

### Benchmark Data

With 10,000 files (~1KB each):
- **Time to hash all files:** ~2.5 seconds
- **I/O overhead:** Reading 10MB of data

This is our baseline. We'll make it 10x faster in the next lesson.

---

## Sub-lesson 1.2: mtime Optimization

### The Problem

Reading 10,000 files takes ~2.5 seconds even when nothing changed. That's unacceptable for incremental builds.

```
Current situation:
┌─────────────────────────────────────────────────────────────────────┐
│  Build 1: Change file_0001.mini                                     │
│  Build 2: Change nothing                                            │
│                                                                     │
│  Both builds read ALL 10,000 files to check if they changed!        │
│  99.99% of that I/O is wasted.                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Solution

Use the file's **modification time (mtime)** as a fast first check. Reading mtime requires only a `stat()` system call - no file reading.

```
OPTIMIZED APPROACH:
For each file:
    1. Get mtime (fast - just stat())
    2. If mtime == cached_mtime:
           → File unchanged, use cached hash
    3. Else:
           → Read file, compute hash, update cache
```

**Updated Data Structures:**

```
FileHashEntry {
    mtime: i128         // File modification time (nanoseconds)
    hash: u64           // Content hash
}

FileHashCache {
    entries: Map<path, FileHashEntry>
    dirty: bool         // True if cache needs saving
}
```

**Why nanoseconds for mtime?**
- Most filesystems support nanosecond precision
- Avoids false negatives from sub-second edits
- Use your OS's highest precision timestamp

**Updated Cache Logic:**

```
FileHashCache.ensureCached(self, path) -> FileHashEntry {
    // Get current mtime (fast!)
    current_mtime = getFileMtime(path)

    // Check if we have a cached entry
    if self.entries.get(path) -> entry {
        // Mtime unchanged? Cache is valid!
        if entry.mtime == current_mtime {
            return entry  // No file read needed
        }

        // Mtime changed - update cache
        source = read_file(path)
        entry.mtime = current_mtime
        entry.hash = hashSource(source)
        self.dirty = true
        return entry
    }

    // New file - create entry
    source = read_file(path)
    entry = FileHashEntry {
        mtime: current_mtime,
        hash: hashSource(source),
    }
    self.entries.put(path, entry)
    self.dirty = true
    return entry
}

getFileMtime(path) -> i128 {
    file = open(path)
    stat = file.stat()
    file.close()
    return stat.mtime  // Nanoseconds since epoch
}
```

**Key Insight:**
```
┌─────────────────────────────────────────────────────────────────────┐
│  With mtime checking:                                               │
│                                                                     │
│  10,000 files:                                                      │
│  ├── stat() each file: ~300ms (just metadata)                       │
│  ├── Read changed files: ~0ms (usually 0-1 files)                   │
│  └── Total: ~300ms                                                  │
│                                                                     │
│  Without mtime checking:                                            │
│  ├── Read all files: ~2,500ms                                       │
│  └── Total: ~2,500ms                                                │
│                                                                     │
│  Speedup: ~8x faster!                                               │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Update `FileHashEntry` to include `mtime`
2. Implement `getFileMtime()` using your language's file stat API
3. Update `ensureCached()` with the mtime check
4. Test:

```
// Test: mtime caching avoids file reads
cache = FileHashCache.init()

// First call - reads file
entry1 = cache.ensureCached("test.mini")
read_count_1 = get_read_count()  // Track with logging or counter

// Second call - should NOT read file
entry2 = cache.ensureCached("test.mini")
read_count_2 = get_read_count()

assert read_count_1 == 1
assert read_count_2 == 1  // Still 1, not 2!
assert entry1.hash == entry2.hash
```

### Benchmark Data

| Scenario | Without mtime | With mtime | Speedup |
|----------|--------------|------------|---------|
| 10K files, none changed | 2,555ms | 300ms | **8.5x** |
| 10K files, 1 changed | 2,555ms | 305ms | **8.4x** |
| 10K files, cold cache | 2,555ms | 2,555ms | 1x |

The mtime optimization only helps on subsequent builds, but that's exactly when it matters!

---

## Sub-lesson 1.3: Import Tracking

### The Problem

A file can change without being directly modified. If `main.mini` imports `math.mini`, and `math.mini` changes, `main.mini` needs recompilation too.

```
Dependency chain:
    main.mini → imports → math.mini → imports → utils.mini

If utils.mini changes:
    → math.mini needs recompilation (uses utils.mini)
    → main.mini needs recompilation (uses math.mini)
```

We need to track what each file imports.

### The Solution

Extract import statements from each file and store them in the cache entry.

**Updated Data Structure:**

```
FileHashEntry {
    mtime: i128                 // File modification time
    hash: u64                   // Content hash
    imports: []string           // List of imported file paths
}
```

**Import Extraction:**

Parse the source to find import statements. This is language-specific, but here's a simple approach for our `.mini` syntax:

```
// Syntax: import "path/to/file.mini" as alias;

extractImports(source) -> []string {
    imports = []

    // Simple parser - find "import" followed by quoted path
    i = 0
    while i < source.length {
        // Look for "import" keyword
        if source[i..i+6] == "import" {
            i += 6

            // Skip whitespace
            while source[i] in [' ', '\t'] {
                i += 1
            }

            // Expect opening quote
            if source[i] == '"' {
                i += 1
                start = i

                // Find closing quote
                while source[i] != '"' {
                    i += 1
                }

                path = source[start..i]
                imports.append(path)
            }
        }
        i += 1
    }

    return imports
}
```

**Updated ensureCached:**

```
FileHashCache.ensureCached(self, path) -> FileHashEntry {
    current_mtime = getFileMtime(path)

    if self.entries.get(path) -> entry {
        if entry.mtime == current_mtime {
            return entry  // Imports haven't changed either
        }

        // Mtime changed - re-read everything
        source = read_file(path)
        entry.mtime = current_mtime
        entry.hash = hashSource(source)
        entry.imports = extractImports(source)  // NEW!
        self.dirty = true
        return entry
    }

    source = read_file(path)
    entry = FileHashEntry {
        mtime: current_mtime,
        hash: hashSource(source),
        imports: extractImports(source),  // NEW!
    }
    self.entries.put(path, entry)
    self.dirty = true
    return entry
}
```

**Getting Imports:**

```
FileHashCache.getImports(self, path) -> []string {
    entry = self.ensureCached(path)
    return entry.imports
}
```

### Try It Yourself

1. Implement `extractImports()` for your language's syntax
2. Update `FileHashEntry` to include imports
3. Update `ensureCached()` to extract imports
4. Test:

```
// Test: Import extraction
source = '''
import "math.mini" as math;
import "utils.mini" as utils;

fn main() i32 {
    return math.add(1, 2);
}
'''

imports = extractImports(source)
assert imports == ["math.mini", "utils.mini"]
```

### Why Not Use the AST?

You might wonder: "Why parse imports separately? The compiler already parses the AST."

Good question! We extract imports **before** full parsing because:
1. **Speed** - Simple string scanning is faster than full AST parsing
2. **Independence** - We need imports to decide WHAT to compile
3. **Minimal work** - If mtime matches, we skip both extraction AND parsing

```
Build flow:
1. Check mtime for all files (fast stat() calls)
2. For changed files: extract imports + hash
3. Build dependency graph
4. Decide what needs recompilation
5. THEN do full parsing/compilation
```

### Benchmark Data

| Operation | Time (10K files) |
|-----------|-----------------|
| Extract imports (per file) | ~0.1ms |
| Full AST parse (per file) | ~0.5ms |

Import extraction is ~5x faster than full parsing.

---

## Sub-lesson 1.4: Binary Persistence

### The Problem

The cache is useless if it's gone when the program exits. We need to save it to disk and load it on the next build.

JSON is the obvious choice, but for 10,000 files it's too slow:

```
JSON format:
{
  "files/file_00001.mini": {
    "mtime": 1703789456000000000,
    "hash": 12345678901234567,
    "imports": ["file_00002.mini", "file_00003.mini"]
  },
  ...
}

Problems:
- 10K entries = ~2MB JSON file
- Parse time: ~500ms (too slow!)
- String allocations: thousands
```

### The Solution

Use a simple binary format with length-prefixed strings.

**Binary Format:**

```
┌────────────────────────────────────────────────────────────────────┐
│ BINARY CACHE FORMAT                                                │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ Header:                                                            │
│   [8 bytes] entry_count (u64, little-endian)                       │
│                                                                    │
│ For each entry:                                                    │
│   [4 bytes] path_length (u32)                                      │
│   [N bytes] path (UTF-8 string, no null terminator)                │
│   [16 bytes] mtime (i128, little-endian)                           │
│   [8 bytes] hash (u64, little-endian)                              │
│   [4 bytes] imports_count (u32)                                    │
│   For each import:                                                 │
│     [4 bytes] import_length (u32)                                  │
│     [M bytes] import_path (UTF-8 string)                           │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Save Function:**

```
FileHashCache.save(self, cache_dir) {
    if not self.dirty {
        return  // Nothing changed
    }

    ensure_directory_exists(cache_dir)
    path = cache_dir + "/file_hashes.bin"
    file = create_file(path)

    // Write entry count
    write_u64(file, self.entries.count())

    for (entry_path, entry) in self.entries {
        // Write path
        write_u32(file, entry_path.length)
        write_bytes(file, entry_path)

        // Write mtime and hash
        write_i128(file, entry.mtime)
        write_u64(file, entry.hash)

        // Write imports
        write_u32(file, entry.imports.length)
        for import_path in entry.imports {
            write_u32(file, import_path.length)
            write_bytes(file, import_path)
        }
    }

    file.close()
    self.dirty = false
}
```

**Load Function:**

```
FileHashCache.load(self, cache_dir) {
    path = cache_dir + "/file_hashes.bin"

    if not file_exists(path) {
        return  // No cache yet
    }

    file = open_file(path)

    // Read entry count
    count = read_u64(file)

    for _ in 0..count {
        // Read path
        path_len = read_u32(file)
        entry_path = read_bytes(file, path_len)

        // Read mtime and hash
        mtime = read_i128(file)
        hash = read_u64(file)

        // Read imports
        imports_count = read_u32(file)
        imports = []
        for _ in 0..imports_count {
            import_len = read_u32(file)
            imports.append(read_bytes(file, import_len))
        }

        self.entries.put(entry_path, FileHashEntry {
            mtime: mtime,
            hash: hash,
            imports: imports,
        })
    }

    file.close()
}
```

**Helper Functions:**

```
write_u32(file, value) {
    bytes = [4]u8
    // Little-endian encoding
    bytes[0] = (value >> 0) & 0xFF
    bytes[1] = (value >> 8) & 0xFF
    bytes[2] = (value >> 16) & 0xFF
    bytes[3] = (value >> 24) & 0xFF
    file.write(bytes)
}

read_u32(file) -> u32 {
    bytes = file.read(4)
    return (bytes[0] << 0) |
           (bytes[1] << 8) |
           (bytes[2] << 16) |
           (bytes[3] << 24)
}

// Similar for u64, i128...
```

### Try It Yourself

1. Implement `save()` and `load()` with binary format
2. Test round-trip:

```
// Test: Save and load
cache1 = FileHashCache.init()
cache1.ensureCached("test.mini")
cache1.save(".cache")

cache2 = FileHashCache.init()
cache2.load(".cache")

assert cache2.entries.count() == 1
assert cache2.entries.get("test.mini").hash == cache1.entries.get("test.mini").hash
```

3. Test that dirty flag prevents unnecessary writes:

```
cache = FileHashCache.init()
cache.load(".cache")
// No changes made
cache.save(".cache")  // Should be a no-op

// Check file wasn't rewritten (mtime unchanged)
```

### Benchmark Data

| Format | File Size (10K entries) | Load Time | Save Time |
|--------|------------------------|-----------|-----------|
| JSON | ~2MB | ~500ms | ~300ms |
| Binary | ~400KB | ~50ms | ~30ms |
| **Speedup** | **5x smaller** | **10x faster** | **10x faster** |

Binary format is strictly better for caches. Save JSON for debugging if needed.

---

## Sub-lesson 1.5: Combined Hash

### The Problem

We can detect when a file changes. But what about its dependencies?

```
Scenario:
    main.mini imports math.mini
    math.mini imports utils.mini

    You modify utils.mini

    Question: Does main.mini's cache entry know it's stale?
    Answer: NO! main.mini's mtime and hash haven't changed!
```

We need a hash that includes **all transitive dependencies**.

### The Solution

The **combined hash** is a hash of:
- The file's own content
- All of its imports' content (recursively)

```
┌────────────────────────────────────────────────────────────────────┐
│ COMBINED HASH                                                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ combined_hash(main.mini) = hash(                                   │
│     main.mini content +                                            │
│     math.mini content +      // direct import                      │
│     utils.mini content       // transitive import                  │
│ )                                                                  │
│                                                                    │
│ If ANY file in the chain changes, combined_hash changes.           │
│ This ensures we never use stale cache entries.                     │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
computeCombinedHash(cache, path, base_dir) -> u64 {
    hasher = Hasher.init()
    visited = Set<string>{}

    // Start with the main file
    source = read_file(resolve_path(base_dir, path))
    hasher.update(source)

    // Add all transitive dependencies
    addTransitiveDeps(cache, path, base_dir, hasher, visited)

    return hasher.final()
}

addTransitiveDeps(cache, path, base_dir, hasher, visited) {
    if visited.contains(path) {
        return  // Avoid infinite loops from circular imports
    }
    visited.add(path)

    // Get imports (uses mtime cache!)
    entry = cache.ensureCached(resolve_path(base_dir, path))

    for import_path in entry.imports {
        // Resolve relative path
        full_path = resolve_path(dirname(path), import_path)

        // Hash the imported file
        import_source = read_file(resolve_path(base_dir, full_path))
        hasher.update(import_source)

        // Recursively add ITS imports
        addTransitiveDeps(cache, full_path, base_dir, hasher, visited)
    }
}
```

**Path Resolution:**

Import paths are relative to the importing file:

```
resolve_path(base, relative) -> string {
    if relative starts with "/" {
        return relative  // Absolute path
    }
    return join_path(base, relative)
}

// Example:
// File: files/file_00001.mini
// Import: "file_00002.mini"
// Resolved: files/file_00002.mini
```

**Using Combined Hash:**

```
// In your build system:
combined_hash = computeCombinedHash(hash_cache, "main.mini", ".")

// Check if we have cached output for this combined hash
if zir_cache.hasMatchingHash("main.mini", combined_hash) {
    // Use cached output - nothing changed!
    return zir_cache.getLlvmIr("main.mini", combined_hash)
}

// Something changed - need to recompile
// (But we don't know WHAT changed yet - that's surgical patching, Module 5)
```

### Optimization: Hash of Hashes

For very large dependency trees, you can optimize by hashing the individual file hashes instead of re-reading all content:

```
computeCombinedHashFast(cache, path, base_dir) -> u64 {
    hasher = Hasher.init()
    visited = Set<string>{}

    addTransitiveHashes(cache, path, base_dir, hasher, visited)

    return hasher.final()
}

addTransitiveHashes(cache, path, base_dir, hasher, visited) {
    if visited.contains(path) {
        return
    }
    visited.add(path)

    // Use cached hash instead of re-reading file
    entry = cache.ensureCached(resolve_path(base_dir, path))
    hasher.update(entry.hash as bytes)  // Hash the hash!

    for import_path in entry.imports {
        full_path = resolve_path(dirname(path), import_path)
        addTransitiveHashes(cache, full_path, base_dir, hasher, visited)
    }
}
```

This avoids re-reading files when computing the combined hash, using the cached per-file hashes instead.

### Try It Yourself

1. Implement `computeCombinedHash()`
2. Test with this dependency chain:

```
// Create test files:
// main.mini:
import "math.mini" as math;
fn main() i32 { return math.add(1, 2); }

// math.mini:
import "utils.mini" as utils;
fn add(a: i32, b: i32) i32 { return utils.helper(a) + b; }

// utils.mini:
fn helper(x: i32) i32 { return x; }

// Test 1: Combined hash includes all files
cache = FileHashCache.init()
hash1 = computeCombinedHash(cache, "main.mini", ".")

// Test 2: Changing main.mini changes combined hash
modify("main.mini", "// comment")
hash2 = computeCombinedHash(cache, "main.mini", ".")
assert hash1 != hash2

// Test 3: Changing utils.mini ALSO changes main.mini's combined hash!
reset_files()
hash3 = computeCombinedHash(cache, "main.mini", ".")
modify("utils.mini", "// changed")
hash4 = computeCombinedHash(cache, "main.mini", ".")
assert hash3 != hash4  // This is the key test!
```

### Benchmark Data

| Operation | Time (10K files, avg 2 imports each) |
|-----------|-------------------------------------|
| Compute combined hash (read all) | ~500ms |
| Compute combined hash (use cached hashes) | ~50ms |
| **With mtime optimization** | **~5ms** |

The mtime optimization compounds beautifully with combined hashes.

---

## Summary: What You've Built

```
┌────────────────────────────────────────────────────────────────────┐
│ FileHashCache - Complete Implementation                            │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ FileHashEntry {                                                    │
│     mtime: i128           // For fast change detection             │
│     hash: u64             // Content hash                          │
│     imports: []string     // Dependency tracking                   │
│ }                                                                  │
│                                                                    │
│ FileHashCache {                                                    │
│     entries: Map<path, FileHashEntry>                              │
│     dirty: bool                                                    │
│                                                                    │
│     ensureCached(path) -> FileHashEntry  // mtime-optimized        │
│     getHash(path) -> u64                                           │
│     getImports(path) -> []string                                   │
│     load(cache_dir)                      // Binary format          │
│     save(cache_dir)                      // Binary format          │
│ }                                                                  │
│                                                                    │
│ computeCombinedHash(cache, path, base_dir) -> u64                  │
│     // Includes all transitive dependencies                        │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Performance Summary:**

| Optimization | Impact |
|-------------|--------|
| mtime checking | 8-10x faster change detection |
| Binary format | 10x faster cache load/save |
| Combined hash | Correct cache invalidation |
| Hash of hashes | Fast combined hash computation |

---

## Next Steps

You now have reliable, fast change detection. But what do we do when we detect a change? That's where caching compiled output comes in.

**Next: [Module 2: File-Level Cache](../02-file-cache/)** - Store and retrieve compiled IR

---

## Complete Code Reference

For a complete implementation, see the reference files:
- `src/cache.zig` - `FileHashCache` struct and methods
- `src/main.zig` - `computeCombinedHash()` function

Key functions:
- `hashSource()` - WyHash content hashing
- `getFileMtime()` - File modification time
- `extractImports()` - Import statement parsing
- `FileHashCache.load()` / `save()` - Binary persistence
- `computeCombinedHash()` - Transitive dependency hashing
