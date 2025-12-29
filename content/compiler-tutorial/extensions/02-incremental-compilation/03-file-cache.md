---
title: "2.3: File Cache"
weight: 3
---

# Lesson 2.3: File Cache

Let's build a cache that stores compiled output for each file.

---

## Goal

Create a file-level cache that:
- Stores LLVM IR output per file
- Persists to disk between compiler runs
- Tracks dependencies
- Knows when to invalidate

---

## Cache Data Structures

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         FILE CACHE STRUCTURE                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Cache {                                                                    │
│       cache_dir:  ".mini_cache",                                             │
│       entries:    Map<path, CacheEntry>,                                     │
│   }                                                                          │
│                                                                              │
│   CacheEntry {                                                               │
│       path:         "main.mini",                                             │
│       mtime:        1703789456,        // Last modification time             │
│       compiled_at:  1703789500,        // When we compiled it                │
│       hash:         0x8a3f2b1c,        // Content hash                       │
│       llvm_ir:      "define i32...",   // Cached output                      │
│       dependencies: ["math.mini"],     // Files we import                    │
│       dirty:        false,             // Needs recompilation?               │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Define the Cache Structure

```
Cache = struct {
    allocator:  Allocator,
    cache_dir:  string,
    entries:    Map<string, CacheEntry>,
}

CacheEntry = struct {
    path:         string,
    mtime:        i128,
    compiled_at:  i128,
    hash:         u64,
    llvm_ir:      string | null,
    dependencies: []string,
    dirty:        bool,
}
```

---

## Step 2: Initialize the Cache

```
Cache.init(allocator, cache_dir) -> Cache {
    return Cache {
        allocator: allocator,
        cache_dir: cache_dir,
        entries: empty_map,
    }
}
```

---

## Step 3: Update Cache Entry

After compiling a file, update its cache entry:

```
Cache.update(self, path, llvm_ir, dependencies) {
    mtime = getFileMtime(path)
    compiled_at = current_timestamp()
    hash = wyhash(llvm_ir)

    entry = CacheEntry {
        path: path,
        mtime: mtime,
        compiled_at: compiled_at,
        hash: hash,
        llvm_ir: copy(llvm_ir),
        dependencies: copy(dependencies),
        dirty: false,
    }

    self.entries.put(path, entry)

    // Also save LLVM IR to cache file
    self.saveLLVMIR(path, llvm_ir)
}
```

---

## Step 4: Save Cache to Disk

Store cache metadata in JSON:

```
Cache.save(self) {
    // Create cache directory
    mkdir(self.cache_dir)

    // Write manifest.json
    manifest_path = format("{}/manifest.json", self.cache_dir)
    file = create_file(manifest_path)

    write_json(file, {
        "files": [
            for entry in self.entries {
                {
                    "path": entry.path,
                    "mtime": entry.mtime,
                    "compiled_at": entry.compiled_at,
                    "hash": entry.hash,
                    "dependencies": entry.dependencies,
                }
            }
        ]
    })
}

Cache.saveLLVMIR(self, path, llvm_ir) {
    // Convert path to cache filename: main.mini -> main.mini.ll
    cache_path = format("{}/{}.ll", self.cache_dir, sanitize(path))
    write_file(cache_path, llvm_ir)
}
```

---

## Step 5: Load Cache from Disk

On compiler startup, load the previous cache:

```
Cache.load(self) {
    manifest_path = format("{}/manifest.json", self.cache_dir)

    // No cache yet? That's fine
    if not file_exists(manifest_path) {
        return
    }

    content = read_file(manifest_path)
    manifest = parse_json(content)

    for file_entry in manifest.files {
        // Try to load the cached LLVM IR
        llvm_ir = self.loadCachedLLVMIR(file_entry.path)

        entry = CacheEntry {
            path: file_entry.path,
            mtime: file_entry.mtime,
            compiled_at: file_entry.compiled_at,
            hash: file_entry.hash,
            llvm_ir: llvm_ir,
            dependencies: file_entry.dependencies,
            dirty: false,
        }

        self.entries.put(file_entry.path, entry)
    }
}
```

---

## Step 6: Invalidate Dependents

When a file changes, mark files that depend on it as dirty:

```
Cache.invalidateDependents(self, changed_path) {
    for entry in self.entries {
        for dep in entry.dependencies {
            if dep == changed_path {
                entry.dirty = true
                // Recursively invalidate
                self.invalidateDependents(entry.path)
                break
            }
        }
    }
}
```

---

## Step 7: Get Cached Output

```
Cache.getCachedLLVMIR(self, path) -> string | null {
    entry = self.entries.get(path)
    if entry == null {
        return null
    }
    return entry.llvm_ir
}
```

---

## Directory Structure

```
.mini_cache/
├── manifest.json          # Cache metadata
├── main.mini.ll          # Cached LLVM IR for main.mini
├── math.mini.ll          # Cached LLVM IR for math.mini
└── tests_utils.mini.ll   # Cached LLVM IR for tests/utils.mini
```

Example manifest.json:
```json
{
  "files": [
    {
      "path": "main.mini",
      "mtime": 1703789456000000000,
      "compiled_at": 1703789500000000000,
      "hash": 12345678901234,
      "dependencies": ["math.mini"]
    },
    {
      "path": "math.mini",
      "mtime": 1703788000000000000,
      "compiled_at": 1703789500000000000,
      "hash": 98765432109876,
      "dependencies": []
    }
  ]
}
```

---

## Verify Your Implementation

### Test 1: Cache init
```
cache = Cache.init(allocator, ".test_cache")
Check: cache.entries.count() == 0
```

### Test 2: Update and retrieve
```
cache.update("test.mini", "define i32 @main...", [])
ir = cache.getCachedLLVMIR("test.mini")
Check: ir == "define i32 @main..."
```

### Test 3: Save and load
```
cache1 = Cache.init(allocator, ".test_cache")
cache1.update("test.mini", "output", [])
cache1.save()

cache2 = Cache.init(allocator, ".test_cache")
cache2.load()
Check: cache2.getCachedLLVMIR("test.mini") == "output"
```

---

## What's Next

File-level caching is great, but we can be even more granular. Let's cache individual functions.

Next: [Lesson 2.4: Function Cache](../04-function-cache/) →
