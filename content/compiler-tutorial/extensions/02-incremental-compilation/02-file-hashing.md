---
title: "2.2: File Hashing"
weight: 2
---

# Lesson 2.2: File Hashing

How do we know if a file has changed? We need reliable change detection.

---

## Goal

Implement functions to:
- Get file modification time (mtime)
- Hash file contents
- Detect if a file needs recompilation

---

## Two Methods for Change Detection

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         CHANGE DETECTION METHODS                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Method 1: MODIFICATION TIME (mtime)                                        │
│   ───────────────────────────────────                                        │
│   - Fast: just read file metadata                                            │
│   - Unreliable: "touch" changes mtime without changing content               │
│   - Good for: quick first check                                              │
│                                                                              │
│   Method 2: CONTENT HASH                                                     │
│   ──────────────────────                                                     │
│   - Slower: must read entire file                                            │
│   - Reliable: only changes when content actually changes                     │
│   - Good for: confirming real changes                                        │
│                                                                              │
│   Best approach: Check mtime first (fast), hash if mtime differs (reliable)  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Get File Modification Time

```
getFileMtime(path) -> timestamp {
    file = open(path)
    defer file.close()

    stat = file.stat()
    return stat.mtime  // Nanoseconds since epoch
}
```

Usage:
```
old_mtime = cache.get(path).mtime
current_mtime = getFileMtime(path)

if current_mtime != old_mtime {
    // File might have changed - check hash to be sure
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

Or with manual implementation:

```
hashSource(source) -> u64 {
    hasher = Hasher.init(seed: 0)
    hasher.update(source)
    return hasher.final()
}
```

Properties we need:
- **Fast**: We hash on every build
- **Collision-resistant**: Different files should have different hashes
- **Deterministic**: Same content always produces same hash

We don't need cryptographic security - WyHash, xxHash, or similar are perfect.

---

## Step 3: Hash Function ZIR (for per-function caching)

For per-function caching, we hash the function's intermediate representation:

```
hashFunctionZir(function) -> u64 {
    hasher = Hasher.init(seed: 0)

    // Hash function name
    hasher.update(function.name)

    // Hash parameter types
    for param in function.params {
        hasher.update(param.name)
        hasher.update(param.type)
    }

    // Hash return type
    if function.return_type {
        hasher.update(function.return_type)
    }

    // Hash each instruction
    for inst in function.instructions {
        hasher.update(inst.opcode)

        switch inst {
            .literal => hasher.update(inst.value),
            .add => {
                hasher.update(inst.lhs)
                hasher.update(inst.rhs)
            },
            .call => {
                hasher.update(inst.name)
                for arg in inst.args {
                    hasher.update(arg)
                }
            },
            // ... other instruction types
        }
    }

    return hasher.final()
}
```

---

## Step 4: Needs Recompile Check

Combine mtime and hash checking:

```
needsRecompile(cache, path) -> bool {
    // No cache entry? Definitely need to compile
    entry = cache.get(path)
    if entry == null {
        return true
    }

    // Check mtime first (fast)
    current_mtime = getFileMtime(path)
    if current_mtime != entry.mtime {
        return true
    }

    // Check if dependencies changed
    for dep in entry.dependencies {
        dep_mtime = getFileMtime(dep)
        // If dependency changed AFTER we compiled, recompile
        if dep_mtime > entry.compiled_at {
            return true
        }
    }

    return false
}
```

---

## Handling Dependencies

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         DEPENDENCY CHECKING                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   main.mini imports math.mini                                                │
│                                                                              │
│   Cache for main.mini:                                                       │
│   {                                                                          │
│       path: "main.mini",                                                     │
│       mtime: 1703789456,                                                     │
│       compiled_at: 1703789500,  ◄── When we last compiled                    │
│       dependencies: ["math.mini"],                                           │
│   }                                                                          │
│                                                                              │
│   If math.mini's mtime > main.mini's compiled_at:                            │
│       → math.mini changed AFTER we compiled main.mini                        │
│       → main.mini needs recompilation                                        │
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

### Test 3: Mtime detection
```
// Create file, record mtime
write_file("test.mini", "content")
mtime1 = getFileMtime("test.mini")

// Wait, then modify
sleep(1ms)
write_file("test.mini", "new content")
mtime2 = getFileMtime("test.mini")

Check: mtime2 > mtime1
```

---

## What's Next

Now let's build the file cache structure.

Next: [Lesson 2.3: File Cache](../03-file-cache/) →
