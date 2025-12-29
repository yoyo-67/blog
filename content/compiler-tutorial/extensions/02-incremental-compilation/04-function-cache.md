---
title: "2.4: Function Cache"
weight: 4
---

# Lesson 2.4: Function Cache (AirCache)

File-level caching helps, but we can do better. Let's cache individual functions so that changing one function doesn't recompile others in the same file.

---

## Goal

Build an `AirCache` that:
- Caches LLVM IR for individual functions
- Uses ZIR hash (function's intermediate representation) as the key
- Uses Git-style object storage like ZirCache
- Integrates with codegen via a `CachedCodegen` wrapper

---

## Why Per-Function Caching?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         FILE vs FUNCTION CACHING                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   math.mini has 3 functions: add, sub, mul                                   │
│   You modify only mul()                                                      │
│                                                                              │
│   FILE CACHE (ZirCache):           FUNCTION CACHE (AirCache):               │
│   ─────────────────────            ───────────────────────────               │
│   math.mini's combined hash        add() ZIR hash unchanged                  │
│   changed (content changed)            → use cached LLVM IR                  │
│        │                           sub() ZIR hash unchanged                  │
│        ▼                               → use cached LLVM IR                  │
│   Recompile all 3 functions        mul() ZIR hash changed                    │
│                                        → recompile                           │
│                                                                              │
│   Work: 3 functions                Work: 1 function                          │
│                                                                              │
│   Function cache = 3x faster!                                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## AirCache Structure

```
AirCache {
    cache_dir:    string,
    objects_dir:  string,                        // e.g., ".mini_cache/objects"
    index:        Map<string, u64>,              // "path:funcname" -> zir_hash
    loaded_count: usize,
}
```

---

## Step 1: Hash Function ZIR

The key insight: hash the function's **intermediate representation**, not the source text. This means whitespace and comments don't affect the hash.

```
hashFunctionZir(function) -> u64 {
    hasher = Hasher.init(seed: 0)

    // Hash function name
    hasher.update(function.name)

    // Hash parameter names and types
    for param in function.params {
        hasher.update(param.name)
        hasher.update(byte(param.type))  // Type enum as byte
    }

    // Hash return type
    if function.return_type {
        hasher.update(byte(function.return_type))
    }

    // Hash each instruction in the function body
    for inst in function.instructions {
        hasher.update(byte(inst.opcode))

        switch inst {
            .literal => |lit| {
                switch lit.value {
                    .int => hasher.update(bytes(lit.value)),
                    .float => hasher.update(bytes(lit.value)),
                    .bool => hasher.update(byte(lit.value)),
                    .string => hasher.update(lit.value),
                }
            },

            .add, .sub, .mul, .div => |op| {
                hasher.update(bytes(op.lhs))  // Operand indices
                hasher.update(bytes(op.rhs))
            },

            .call => |c| {
                hasher.update(c.function_name)
                for arg in c.args {
                    hasher.update(bytes(arg))
                }
            },

            .return_stmt => |r| {
                hasher.update(bytes(r.value))
            },

            .declare => |d| {
                hasher.update(d.name)
                hasher.update(bytes(d.value))
            },

            // ... handle all instruction types
        }
    }

    return hasher.final()
}
```

---

## What Changes Affect the Hash?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         HASH CHANGE EXAMPLES                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CHANGES THAT AFFECT HASH:                                                  │
│   ─────────────────────────                                                  │
│   • Change function body:  return a + b  →  return a - b                     │
│   • Change parameter types: (a: i32)  →  (a: i64)                            │
│   • Change return type:    fn foo() i32  →  fn foo() bool                    │
│   • Add/remove instructions                                                  │
│   • Change literal values: 42 → 43                                           │
│   • Change called function: call foo() → call bar()                          │
│                                                                              │
│   CHANGES THAT DON'T AFFECT HASH:                                            │
│   ───────────────────────────────                                            │
│   • Whitespace changes (hashing ZIR, not source)                             │
│   • Comments (not in ZIR)                                                    │
│   • Other functions in the same file                                         │
│   • Renaming local variables (if your ZIR uses indices)                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 2: AirCache Operations

```
AirCache.init(cache_dir) -> AirCache {
    return AirCache {
        cache_dir: cache_dir,
        objects_dir: format("{}/objects", cache_dir),
        index: empty_map,
        loaded_count: 0,
    }
}

AirCache.makeKey(file_path, func_name) -> string {
    return format("{}:{}", file_path, func_name)
}

AirCache.get(self, file_path, func_name, zir_hash) -> string | null {
    key = self.makeKey(file_path, func_name)

    // Check if we have this function cached with matching hash
    if self.index.get(key) -> cached_hash {
        if cached_hash == zir_hash {
            // Hash matches - read from object file
            object_path = hashToPath(self.objects_dir, zir_hash)
            if file_exists(object_path) {
                return read_file(object_path)
            }
        }
    }

    return null  // Cache miss
}

AirCache.put(self, file_path, func_name, zir_hash, llvm_ir) {
    key = self.makeKey(file_path, func_name)

    // Update index
    self.index.put(key, zir_hash)

    // Write to object file immediately (write-on-put)
    object_path = hashToPath(self.objects_dir, zir_hash)
    mkdir_p(dirname(object_path))
    write_file(object_path, llvm_ir)
}
```

---

## Git-Style Storage (Same as ZirCache)

```
hashToPath(objects_dir, hash) -> string {
    hex = format("{:016x}", hash)
    return format("{}/{}/{}", objects_dir, hex[0..2], hex[2..16])
}

// Example:
// hash = 0x9a2eb98b6d927e93
// path = ".mini_cache/objects/9a/2eb98b6d927e93"
```

---

## Step 3: CachedCodegen Wrapper

Wrap the code generator to transparently use the cache:

```
CachedCodegen {
    allocator:  Allocator,
    air_cache:  *AirCache,
    file_path:  string,
    stats:      Stats,
}

Stats {
    functions_total:    usize,
    functions_cached:   usize,   // Cache hits
    functions_compiled: usize,   // Cache misses
}

CachedCodegen.init(allocator, air_cache, file_path) -> CachedCodegen {
    return CachedCodegen {
        allocator: allocator,
        air_cache: air_cache,
        file_path: file_path,
        stats: Stats { 0, 0, 0 },
    }
}

CachedCodegen.generate(self, program) -> string {
    output = []

    for function in program.functions {
        self.stats.functions_total += 1

        // Compute ZIR hash for this function
        zir_hash = hashFunctionZir(function)

        // Check cache
        cached_ir = self.air_cache.get(
            self.file_path,
            function.name,
            zir_hash
        )

        if cached_ir != null {
            // CACHE HIT - use cached output
            self.stats.functions_cached += 1
            output.append(cached_ir)
        } else {
            // CACHE MISS - compile and cache
            self.stats.functions_compiled += 1

            func_ir = generateSingleFunction(function)

            // Store in cache for next time
            self.air_cache.put(
                self.file_path,
                function.name,
                zir_hash,
                func_ir
            )

            output.append(func_ir)
        }
    }

    return join(output, "\n\n")
}
```

---

## Step 4: Save/Load Index

```
AirCache.save(self) {
    // Note: Object files are written immediately in put()
    // We only need to save the index

    index_path = format("{}/air_index.bin", self.cache_dir)
    file = create_file(index_path)

    file.writeU32(self.index.count())

    for (key, hash) in self.index {
        file.writeU32(key.len)
        file.writeBytes(key)
        file.writeU64(hash)
    }
}

AirCache.load(self) {
    index_path = format("{}/air_index.bin", self.cache_dir)

    if not file_exists(index_path) {
        return
    }

    file = open_file(index_path)
    count = file.readU32()

    for _ in 0..count {
        key_len = file.readU32()
        key = file.readBytes(key_len)
        hash = file.readU64()

        self.index.put(key, hash)
        self.loaded_count += 1
    }
}
```

---

## Complete Flow Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         PER-FUNCTION CACHING FLOW                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   math.mini has: add(), sub(), mul()                                         │
│   You changed mul() implementation                                           │
│                                                                              │
│   CachedCodegen.generate(program):                                           │
│                                                                              │
│   Function: add()                                                            │
│   ├── zir_hash = 0xaaa111... (unchanged)                                    │
│   ├── cache.get("math.mini", "add", 0xaaa111...)                            │
│   ├── HIT! Return cached IR                                                  │
│   └── stats: cached=1, compiled=0                                           │
│                                                                              │
│   Function: sub()                                                            │
│   ├── zir_hash = 0xbbb222... (unchanged)                                    │
│   ├── cache.get("math.mini", "sub", 0xbbb222...)                            │
│   ├── HIT! Return cached IR                                                  │
│   └── stats: cached=2, compiled=0                                           │
│                                                                              │
│   Function: mul()                                                            │
│   ├── zir_hash = 0xccc333... (CHANGED!)                                     │
│   ├── cache.get("math.mini", "mul", 0xccc333...)                            │
│   ├── MISS! Compile function                                                 │
│   ├── cache.put("math.mini", "mul", 0xccc333..., new_ir)                    │
│   └── stats: cached=2, compiled=1                                           │
│                                                                              │
│   Result: Only 1/3 functions compiled!                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
.mini_cache/
├── air_index.bin               # "path:func" -> zir_hash mapping
└── objects/                    # Git-style function object storage
    ├── 9a/
    │   └── 2eb98b6d927e93      # LLVM IR for one function
    ├── aa/
    │   └── a111222333444555    # add() function
    ├── bb/
    │   └── b222333444555666    # sub() function
    └── cc/
        └── c333444555666777    # mul() function
```

---

## Verify Your Implementation

### Test 1: Same function, same hash
```
source = "fn add(a: i32, b: i32) i32 { return a + b; }"

program1 = compile(source)
program2 = compile(source)

hash1 = hashFunctionZir(program1.functions[0])
hash2 = hashFunctionZir(program2.functions[0])

Check: hash1 == hash2
```

### Test 2: Different body, different hash
```
source1 = "fn calc(x: i32) i32 { return x + 1; }"
source2 = "fn calc(x: i32) i32 { return x - 1; }"

hash1 = hashFunctionZir(compile(source1).functions[0])
hash2 = hashFunctionZir(compile(source2).functions[0])

Check: hash1 != hash2
```

### Test 3: Cache hit and miss
```
cache = AirCache.init(".test_cache")
cache.put("test.mini", "add", 0x12345, "define i32 @add...")

// Hit - same hash
ir = cache.get("test.mini", "add", 0x12345)
Check: ir == "define i32 @add..."

// Miss - different hash
ir = cache.get("test.mini", "add", 0x99999)
Check: ir == null
```

### Test 4: CachedCodegen stats
```
cache = AirCache.init(".test_cache")
// Pre-populate cache with one function
cache.put("math.mini", "add", 0xaaa, "cached add ir")

program = compile("fn add() {} fn sub() {}")  // 2 functions
gen = CachedCodegen.init(allocator, cache, "math.mini")

// Assuming add's hash is 0xaaa (matches cache)
// and sub's hash is new
output = gen.generate(program)

Check: gen.stats.functions_cached == 1   // add
Check: gen.stats.functions_compiled == 1  // sub
```

---

## What's Next

Now let's explore surgical patching - a technique to partially rebuild files using embedded markers.

Next: [Lesson 2.5: Surgical Patching](../05-surgical-patching/) →
