---
title: "2.4: Function Cache"
weight: 4
---

# Lesson 2.4: Function Cache

File-level caching helps, but we can do better. Let's cache at the function level.

---

## Goal

Cache LLVM IR for individual functions, so changing one function doesn't recompile others in the same file.

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
│   FILE CACHE:                           FUNCTION CACHE:                      │
│   ───────────                           ───────────────                      │
│   math.mini changed                     add() unchanged → use cache          │
│        │                                sub() unchanged → use cache          │
│        ▼                                mul() changed   → recompile          │
│   Recompile all 3 functions                    │                             │
│                                                ▼                             │
│   Work: 3 functions                     Work: 1 function                     │
│                                                                              │
│   Function cache = 3x faster in this case!                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## AIR Cache Structure

AIR (Analyzed IR) cache stores per-function output:

```
AirCache = struct {
    allocator:  Allocator,
    entries:    Map<string, AirCacheEntry>,
    cache_dir:  string,
}

AirCacheEntry = struct {
    function_key: string,    // "math.mini:add"
    zir_hash:     u64,       // Hash of function's ZIR
    llvm_ir:      string,    // Cached LLVM IR for this function
}
```

---

## Step 1: Hash Function ZIR

To know if a function changed, hash its intermediate representation:

```
hashFunctionZir(function) -> u64 {
    hasher = Hasher.init(seed: 0)

    // Hash function name
    hasher.update(function.name)

    // Hash parameters
    for param in function.params {
        hasher.update(param.name)
        hasher.update(byte(param.type))  // Type as byte
    }

    // Hash return type
    if function.return_type {
        hasher.update(byte(function.return_type))
    }

    // Hash each instruction's structure
    for inst in function.instructions {
        hasher.update(byte(inst.opcode))

        switch inst {
            .literal => |lit| {
                switch lit.value {
                    .int => hasher.update(bytes(lit.value)),
                    .float => hasher.update(bytes(lit.value)),
                    .bool => hasher.update(byte(lit.value)),
                }
            },
            .add, .sub, .mul, .div => |op| {
                hasher.update(bytes(op.lhs))  // Instruction index
                hasher.update(bytes(op.rhs))
            },
            .call => |c| {
                hasher.update(c.name)
                for arg in c.args {
                    hasher.update(bytes(arg))
                }
            },
            .return_stmt => |r| {
                hasher.update(bytes(r.value))
            },
            // ... other instructions
        }
    }

    return hasher.final()
}
```

---

## Step 2: AIR Cache Operations

```
AirCache.init(allocator, cache_dir) -> AirCache {
    return AirCache {
        allocator: allocator,
        entries: empty_map,
        cache_dir: cache_dir,
    }
}

AirCache.get(self, file_path, func_name, zir_hash) -> string | null {
    key = format("{}:{}", file_path, func_name)

    entry = self.entries.get(key)
    if entry == null {
        return null
    }

    // Only return if hash matches (function unchanged)
    if entry.zir_hash == zir_hash {
        return entry.llvm_ir
    }

    return null
}

AirCache.put(self, file_path, func_name, zir_hash, llvm_ir) {
    key = format("{}:{}", file_path, func_name)

    self.entries.put(key, AirCacheEntry {
        function_key: key,
        zir_hash: zir_hash,
        llvm_ir: copy(llvm_ir),
    })
}
```

---

## Step 3: Cached Codegen

Wrap the code generator to use the cache:

```
CachedCodegen = struct {
    allocator:  Allocator,
    air_cache:  *AirCache,
    file_path:  string,
    stats:      Stats,
}

Stats = struct {
    functions_total:    usize,
    functions_cached:   usize,
    functions_compiled: usize,
}

CachedCodegen.generate(self, program) -> string {
    output = []

    for function in program.functions {
        self.stats.functions_total += 1

        // Compute function's ZIR hash
        zir_hash = hashFunctionZir(function)

        // Check cache
        cached_ir = self.air_cache.get(self.file_path, function.name, zir_hash)

        if cached_ir != null {
            // Cache HIT - use cached output
            self.stats.functions_cached += 1
            output.append(cached_ir)
        } else {
            // Cache MISS - compile and cache
            self.stats.functions_compiled += 1

            func_ir = generateSingleFunction(function)

            // Store in cache for next time
            self.air_cache.put(self.file_path, function.name, zir_hash, func_ir)

            output.append(func_ir)
        }
    }

    return join(output, "\n")
}
```

---

## Step 4: Save/Load AIR Cache

Similar to file cache, persist to disk:

```
// air_cache.json
{
  "functions": [
    {
      "key": "math.mini:add",
      "zir_hash": 12345678901234,
      "llvm_ir": "define i32 @math_add(i32 %0, i32 %1) {\n  %3 = add i32 %0, %1\n  ret i32 %3\n}"
    },
    {
      "key": "math.mini:sub",
      "zir_hash": 98765432109876,
      "llvm_ir": "define i32 @math_sub(i32 %0, i32 %1) {\n  %3 = sub i32 %0, %1\n  ret i32 %3\n}"
    }
  ]
}
```

Note: LLVM IR must be escaped in JSON (newlines → `\n`, quotes → `\"`).

---

## When Hashes Change

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         HASH CHANGE EXAMPLES                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CHANGES THAT AFFECT HASH:                                                  │
│   - Change function body: return a + b  →  return a - b                      │
│   - Change parameter types: (a: i32)  →  (a: i64)                            │
│   - Change return type: fn foo() i32  →  fn foo() bool                       │
│   - Add/remove instructions                                                  │
│                                                                              │
│   CHANGES THAT DON'T AFFECT HASH:                                            │
│   - Whitespace changes                                                       │
│   - Comments (if not in ZIR)                                                 │
│   - Other functions in the same file                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Implementation

### Test 1: Same function, same hash
```
source = "fn add(a: i32, b: i32) i32 { return a + b; }"

// Parse and generate ZIR twice
program1 = compile(source)
program2 = compile(source)

hash1 = hashFunctionZir(program1.functions[0])
hash2 = hashFunctionZir(program2.functions[0])

Check: hash1 == hash2
```

### Test 2: Different body, different hash
```
source1 = "fn add(a: i32, b: i32) i32 { return a + b; }"
source2 = "fn add(a: i32, b: i32) i32 { return a - b; }"

hash1 = hashFunctionZir(compile(source1).functions[0])
hash2 = hashFunctionZir(compile(source2).functions[0])

Check: hash1 != hash2
```

### Test 3: Cache hit/miss
```
cache = AirCache.init(allocator, ".cache")
cache.put("test.mini", "add", 12345, "define i32 @add...")

// Hit
ir = cache.get("test.mini", "add", 12345)
Check: ir == "define i32 @add..."

// Miss (different hash)
ir = cache.get("test.mini", "add", 99999)
Check: ir == null
```

---

## What's Next

Let's combine file and function caching into a complete multi-level cache.

Next: [Lesson 2.5: Multi-Level Cache](../05-multi-level-cache/) →
