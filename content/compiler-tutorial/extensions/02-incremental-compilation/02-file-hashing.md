---
title: "2.2: Change Detection"
weight: 2
---

# Lesson 2.2: Change Detection (FileHashCache)

How do we know if a file has changed? We need fast, reliable change detection that also tracks dependencies.

---

## Goal

Build a `FileHashCache` that:
- Detects when files change (via mtime and content hash)
- Extracts import statements from source files
- Supports computing combined hashes (including transitive dependencies)
- Persists to disk in binary format for speed

---

## FileHashCache Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         FILE HASH CACHE                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   FileHashCache {                                                            │
│       entries: Map<path, FileHashEntry>,                                     │
│       dirty: bool,  // needs saving?                                         │
│   }                                                                          │
│                                                                              │
│   FileHashEntry {                                                            │
│       mtime:   i128,           // File modification time (nanoseconds)       │
│       hash:    u64,            // Source code content hash                   │
│       imports: []string,       // Extracted import paths                     │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Get File Modification Time

Check mtime first - it's fast because we only read metadata:

```
getFileMtime(path) -> i128 {
    file = open(path)
    defer file.close()

    stat = file.stat()
    return stat.mtime  // Nanoseconds since epoch
}
```

---

## Step 2: Hash File Contents

Use a fast, non-cryptographic hash like WyHash:

```
hashSource(source) -> u64 {
    return wyhash(seed: 0, data: source)
}
```

Properties we need:
- **Fast**: We hash on every build
- **Collision-resistant**: Different files should have different hashes
- **Deterministic**: Same content always produces same hash

We don't need cryptographic security - WyHash is perfect.

---

## Step 3: Extract Imports

Parse the source to find import statements:

```
extractImports(source) -> []string {
    imports = []

    for line in source.lines() {
        line = line.trim()

        // Look for: import "path/to/file.mini"
        if line.startsWith("import ") {
            // Extract path between quotes
            start = line.indexOf('"')
            end = line.lastIndexOf('"')

            if start != -1 and end > start {
                path = line[start+1..end]
                imports.append(path)
            }
        }
    }

    return imports
}
```

Example:
```
// Source file:
import "math.mini"
import "utils.mini"

fn main() { ... }

// Extracted imports: ["math.mini", "utils.mini"]
```

---

## Step 4: Ensure Entry is Cached

The core logic - check mtime, update if needed:

```
FileHashCache.ensureCached(self, path) -> FileHashEntry {
    current_mtime = getFileMtime(path)

    // Check if we have a cached entry
    if self.entries.get(path) -> entry {
        // Mtime unchanged? Cache is valid
        if entry.mtime == current_mtime {
            return entry
        }

        // Mtime changed - need to update
        source = read_file(path)
        entry.mtime = current_mtime
        entry.hash = hashSource(source)
        entry.imports = extractImports(source)
        self.dirty = true
        return entry
    }

    // No cached entry - create new one
    source = read_file(path)
    entry = FileHashEntry {
        mtime: current_mtime,
        hash: hashSource(source),
        imports: extractImports(source),
    }

    self.entries.put(path, entry)
    self.dirty = true
    return entry
}
```

---

## Step 5: Compute Combined Hash

Include ALL transitive dependencies in the hash:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         COMBINED HASH COMPUTATION                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   main.mini imports: math.mini                                               │
│   math.mini imports: utils.mini                                              │
│                                                                              │
│   computeCombinedHash(main.mini):                                            │
│       hasher = Hasher.init()                                                 │
│       hasher.update(main.mini source)    // Main file                        │
│       hasher.update(math.mini source)    // Direct import                    │
│       hasher.update(utils.mini source)   // Transitive import                │
│       return hasher.final()                                                  │
│                                                                              │
│   If ANY file changes, combined hash changes!                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

```
computeCombinedHash(cache, path, source) -> u64 {
    hasher = Hasher.init()
    visited = Set<string>{}

    // Hash main source
    hasher.update(source)

    // Recursively hash all transitive dependencies
    hashTransitiveDeps(cache, path, hasher, visited)

    return hasher.final()
}

hashTransitiveDeps(cache, path, hasher, visited) {
    if visited.contains(path) {
        return  // Avoid cycles
    }
    visited.add(path)

    // Get imports from cache (uses mtime optimization)
    entry = cache.ensureCached(path)

    for import_path in entry.imports {
        // Hash the imported file's content
        import_entry = cache.ensureCached(import_path)
        import_source = read_file(import_path)
        hasher.update(import_source)

        // Recursively hash its imports
        hashTransitiveDeps(cache, import_path, hasher, visited)
    }
}
```

---

## Step 6: Binary Persistence

Save to binary format for fast loading:

```
FileHashCache.save(self, path) {
    if not self.dirty {
        return  // Nothing changed
    }

    file = create_file(path)  // e.g., "file_hashes.bin"

    // Write entry count
    file.writeInt(self.entries.count())

    for (entry_path, entry) in self.entries {
        // Write path (length-prefixed string)
        file.writeInt(entry_path.len)
        file.writeBytes(entry_path)

        // Write entry data
        file.writeInt128(entry.mtime)
        file.writeU64(entry.hash)

        // Write imports
        file.writeInt(entry.imports.len)
        for import_path in entry.imports {
            file.writeInt(import_path.len)
            file.writeBytes(import_path)
        }
    }

    self.dirty = false
}

FileHashCache.load(self, path) {
    if not file_exists(path) {
        return  // No cache yet
    }

    file = open_file(path)
    count = file.readInt()

    for _ in 0..count {
        // Read path
        path_len = file.readInt()
        entry_path = file.readBytes(path_len)

        // Read entry data
        mtime = file.readInt128()
        hash = file.readU64()

        // Read imports
        imports_len = file.readInt()
        imports = []
        for _ in 0..imports_len {
            import_len = file.readInt()
            imports.append(file.readBytes(import_len))
        }

        self.entries.put(entry_path, FileHashEntry {
            mtime: mtime,
            hash: hash,
            imports: imports,
        })
    }
}
```

---

## Why Binary Format?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         JSON vs BINARY                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   JSON format:                                                               │
│   {                                                                          │
│     "main.mini": {                                                           │
│       "mtime": 1703789456000000000,                                          │
│       "hash": 12345678901234,                                                │
│       "imports": ["math.mini"]                                               │
│     }                                                                        │
│   }                                                                          │
│   Pros: Human-readable, easy to debug                                        │
│   Cons: Slower to parse, larger file size                                    │
│                                                                              │
│   Binary format:                                                             │
│   [entry_count][path_len][path_bytes][mtime][hash][imports...]              │
│   Pros: Very fast to load/save, compact                                      │
│   Cons: Not human-readable                                                   │
│                                                                              │
│   For a cache that loads on EVERY compile, binary wins.                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Implementation

### Test 1: Same content, same hash
```
source1 = "fn main() { return 42; }"
source2 = "fn main() { return 42; }"

hash1 = hashSource(source1)
hash2 = hashSource(source2)

Check: hash1 == hash2
```

### Test 2: Different content, different hash
```
source1 = "fn main() { return 42; }"
source2 = "fn main() { return 43; }"

hash1 = hashSource(source1)
hash2 = hashSource(source2)

Check: hash1 != hash2
```

### Test 3: Import extraction
```
source = '''
import "math.mini"
import "utils.mini"
fn main() {}
'''

imports = extractImports(source)
Check: imports == ["math.mini", "utils.mini"]
```

### Test 4: Mtime caching
```
cache = FileHashCache.init()

// First call - reads file
entry1 = cache.ensureCached("test.mini")

// Second call - uses cached mtime
entry2 = cache.ensureCached("test.mini")

Check: entry1.hash == entry2.hash
Check: only one file read occurred (verify with logging)
```

### Test 5: Combined hash changes with dependency
```
// main.mini imports math.mini
cache = FileHashCache.init()

hash1 = computeCombinedHash(cache, "main.mini", read("main.mini"))

// Modify math.mini
write("math.mini", "modified content")

hash2 = computeCombinedHash(cache, "main.mini", read("main.mini"))

Check: hash1 != hash2  // Combined hash changed!
```

---

## What's Next

Now let's build the file-level cache (ZirCache) that stores LLVM IR using Git-style content-addressed storage.

Next: [Lesson 2.3: File Cache](../03-file-cache/) →
