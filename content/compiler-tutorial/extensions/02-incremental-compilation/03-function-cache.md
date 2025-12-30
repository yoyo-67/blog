---
title: "Module 3: Function-Level Cache"
weight: 3
---

# Module 3: Function-Level Cache (AirCache)

File-level caching skips unchanged files entirely. But when a file DOES change, we recompile ALL its functions. Can we do better?

**What you'll build:**
- Unique function identification scheme
- ZIR-based function hashing (ignores whitespace/comments)
- Per-function content-addressed storage
- A codegen wrapper that uses the cache transparently

**Note:** This module is **nice to have**, not critical. Most build time comes from file-level decisions. Function caching saves 10-50ms per changed file with many functions.

---

## Sub-lesson 3.1: Function Identification

### The Problem

When caching functions, we need a unique key. But function names aren't unique - two files can have functions with the same name:

```
PROBLEM: Function names aren't globally unique

math.mini:
    fn add(a: i32, b: i32) i32 { return a + b; }

string.mini:
    fn add(a: str, b: str) str { return concat(a, b); }

Both have "add" but they're completely different functions!
```

### The Solution

Use a compound key: `"path:function_name"`

```
KEY FORMAT: "{file_path}:{function_name}"

Examples:
    "math.mini:add"
    "string.mini:add"
    "utils.mini:helper"
    "main.mini:main"

Now every function has a globally unique identifier.
```

**Implementation:**

```
makeFunctionKey(file_path, func_name) -> string {
    return format("{}:{}", file_path, func_name)
}

// Examples:
makeFunctionKey("math.mini", "add")
// → "math.mini:add"

makeFunctionKey("lib/utils.mini", "helper")
// → "lib/utils.mini:helper"
```

**Why Include the Path?**

You might think: "Can't I just use `modulename:funcname`?"

Problems with that:
1. Module names can be aliased (`import "math.mini" as m`)
2. Files might not have explicit module names
3. Path is always unique and available

### Try It Yourself

1. Implement `makeFunctionKey()`
2. Test uniqueness:

```
// Test: Different files, same function name
key1 = makeFunctionKey("math.mini", "add")
key2 = makeFunctionKey("string.mini", "add")
assert key1 != key2
assert key1 == "math.mini:add"
assert key2 == "string.mini:add"

// Test: Same file, different functions
key3 = makeFunctionKey("math.mini", "add")
key4 = makeFunctionKey("math.mini", "sub")
assert key3 != key4
```

---

## Sub-lesson 3.2: Function Content Hashing

### The Problem

When should we recompile a function? When its behavior might have changed.

We could hash the source text, but that's fragile:
```
// These are functionally identical:
fn add(a: i32, b: i32) i32 { return a + b; }

fn add(a: i32, b: i32) i32 {
    // This adds two numbers
    return a + b;
}

fn add(a: i32,b: i32) i32 { return a+b; }

Source text hash would differ, but output is the same!
```

### The Solution

Hash the function's **intermediate representation (ZIR)**, not the source text. The ZIR strips away:
- Whitespace
- Comments
- Formatting differences

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT AFFECTS THE HASH                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ CHANGES THAT AFFECT HASH:           CHANGES THAT DON'T:             │
│ ─────────────────────────           ─────────────────────           │
│ • Function name                     • Whitespace                    │
│ • Parameter names and types         • Comments                      │
│ • Return type                       • Formatting                    │
│ • Function body logic               • Other functions in file       │
│ • Literal values (42 → 43)          • Local var names (if using    │
│ • Called functions                    indices in ZIR)               │
│                                                                     │
│ Hash the SEMANTICS, not the SYNTAX                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Hash Implementation:**

```
hashFunctionZir(function) -> u64 {
    hasher = Hasher.init(seed: 0)

    // 1. Hash function name
    hasher.update(function.name)

    // 2. Hash parameter types
    for param in function.params {
        hasher.update(param.name)
        hasher.update(to_bytes(param.type))  // Type enum as byte
    }

    // 3. Hash return type
    if function.return_type != null {
        hasher.update(to_bytes(function.return_type))
    }

    // 4. Hash each instruction
    for inst in function.instructions {
        // Hash opcode
        hasher.update(to_bytes(inst.opcode))

        // Hash operands based on instruction type
        switch inst {
            .literal => |lit| {
                hasher.update(to_bytes(lit.value))
            }

            .add, .sub, .mul, .div => |op| {
                // Hash operand indices
                hasher.update(to_bytes(op.lhs))
                hasher.update(to_bytes(op.rhs))
            }

            .call => |c| {
                hasher.update(c.function_name)
                for arg in c.args {
                    hasher.update(to_bytes(arg))
                }
            }

            .return_stmt => |r| {
                hasher.update(to_bytes(r.value))
            }

            .decl => |d| {
                hasher.update(d.name)
                hasher.update(to_bytes(d.value))
            }

            .decl_ref => |d| {
                hasher.update(d.name)
            }

            .param_ref => |p| {
                hasher.update(to_bytes(p.index))
            }
        }
    }

    return hasher.final()
}
```

**Helper:**

```
to_bytes(value) -> []byte {
    // Convert any value to its byte representation
    // For integers: little-endian bytes
    // For enums: single byte of enum value
    // For strings: raw bytes
}
```

### Try It Yourself

1. Implement `hashFunctionZir()` for your IR
2. Test:

```
// Test 1: Same function → same hash
source1 = "fn add(a: i32, b: i32) i32 { return a + b; }"
source2 = "fn add(a: i32, b: i32) i32 { return a + b; }"

func1 = parse_and_lower(source1).functions[0]
func2 = parse_and_lower(source2).functions[0]

assert hashFunctionZir(func1) == hashFunctionZir(func2)

// Test 2: Different body → different hash
source3 = "fn add(a: i32, b: i32) i32 { return a - b; }"  // sub instead of add
func3 = parse_and_lower(source3).functions[0]

assert hashFunctionZir(func1) != hashFunctionZir(func3)

// Test 3: Different name → different hash
source4 = "fn sub(a: i32, b: i32) i32 { return a + b; }"  // different name
func4 = parse_and_lower(source4).functions[0]

assert hashFunctionZir(func1) != hashFunctionZir(func4)

// Test 4: Whitespace doesn't matter (if using ZIR)
source5 = "fn add(a:i32,b:i32)i32{return a+b;}"  // no spaces
func5 = parse_and_lower(source5).functions[0]

assert hashFunctionZir(func1) == hashFunctionZir(func5)
```

### Benchmark Data

| Hash Input | Collision Risk | Speed |
|------------|---------------|-------|
| Source text | High (formatting changes) | Fast |
| AST | Medium (representation varies) | Medium |
| **ZIR** | **Low (semantic only)** | **Fast** |

ZIR hashing is the sweet spot: fast and semantically meaningful.

---

## Sub-lesson 3.3: Per-Function Storage

### The Problem

We have unique keys and content hashes. Now we need to store and retrieve function IR efficiently.

### The Solution

Use the same Git-style content-addressed storage from Module 2, but keyed by **ZIR hash** instead of combined hash.

**Data Structure:**

```
AirCache {
    cache_dir: string
    objects_dir: string              // e.g., ".cache/objects"
    index: Map<string, u64>          // "path:func" → zir_hash
}
```

**Why Content-Addressed?**

The ZIR hash serves double duty:
1. **Key** - Where to find the cached IR
2. **Validation** - If hash matches, content is valid

```
┌─────────────────────────────────────────────────────────────────────┐
│ CONTENT-ADDRESSED FUNCTION STORAGE                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Store:                                                              │
│   zir_hash = hashFunctionZir(func)    // e.g., 0x9a2eb98b6d927e93   │
│   path = ".cache/objects/9a/2eb98b6d927e93"                         │
│   write(path, llvm_ir)                                              │
│                                                                     │
│ Retrieve:                                                           │
│   zir_hash = hashFunctionZir(func)    // Compute current hash       │
│   path = ".cache/objects/9a/2eb98b6d927e93"                         │
│   if file_exists(path):                                             │
│       return read(path)               // Hash matches = valid!      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
AirCache.init(cache_dir) -> AirCache {
    return AirCache {
        cache_dir: cache_dir,
        objects_dir: format("{}/objects", cache_dir),
        index: empty_map,
    }
}

getObjectPath(objects_dir, hash) -> string {
    hex = format("{:016x}", hash)  // 16 hex chars
    return format("{}/{}/{}", objects_dir, hex[0:2], hex[2:])
}

AirCache.get(self, file_path, func_name, zir_hash) -> string | null {
    // Content-addressed: just look up by hash
    object_path = getObjectPath(self.objects_dir, zir_hash)

    if file_exists(object_path) {
        return read_file(object_path)
    }

    return null
}

AirCache.put(self, file_path, func_name, zir_hash, llvm_ir) {
    // Update index (for stats/debugging)
    key = makeFunctionKey(file_path, func_name)
    self.index.put(key, zir_hash)

    // Write object file
    object_path = getObjectPath(self.objects_dir, zir_hash)
    ensure_directory_exists(dirname(object_path))

    // Skip if already exists (content-addressed = immutable)
    if not file_exists(object_path) {
        write_file(object_path, llvm_ir)
    }
}
```

### Directory Structure

```
.cache/
└── objects/                # Function IR storage
    ├── 9a/
    │   └── 2eb98b6d927e93  # IR for hash 0x9a2eb98b...
    ├── aa/
    │   └── 1234567890abcd  # IR for hash 0xaa12345...
    └── ff/
        └── fedcba0987654   # IR for hash 0xfffedcba...
```

### Try It Yourself

1. Implement `AirCache` with `get()` and `put()`
2. Test:

```
// Test 1: Store and retrieve
cache = AirCache.init(".cache")
ir = "define i32 @add(i32 %a, i32 %b) { ... }"
cache.put("math.mini", "add", 0xabc123, ir)

result = cache.get("math.mini", "add", 0xabc123)
assert result == ir

// Test 2: Miss on different hash
result = cache.get("math.mini", "add", 0x999999)
assert result == null

// Test 3: Object file created correctly
assert file_exists(".cache/objects/ab/c123")
```

### Benchmark Data

| Operation | Time |
|-----------|------|
| Hash function ZIR | ~0.01ms |
| Cache lookup | ~0.1ms |
| Compile function | ~0.5ms |
| **Speedup per cached function** | **5x** |

---

## Sub-lesson 3.4: Cached Code Generation

### The Problem

We have the cache. Now how do we use it? We need to integrate with codegen without making it messy.

### The Solution

Create a `CachedCodegen` wrapper that transparently checks the cache before compiling each function.

```
┌─────────────────────────────────────────────────────────────────────┐
│ CACHED CODEGEN WRAPPER                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ WITHOUT WRAPPER:                    WITH WRAPPER:                   │
│ ────────────────                    ────────────────                │
│                                                                     │
│ for func in program.functions {     codegen = CachedCodegen(cache)  │
│     ir = generateFunction(func)     ir = codegen.generate(program)  │
│     // No caching!                  // Automatic caching!           │
│ }                                                                   │
│                                                                     │
│ Caller handles caching manually     Wrapper handles it all          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Data Structure:**

```
CachedCodegen {
    air_cache: *AirCache
    file_path: string
    stats: Stats
    verbosity: u8          // 0=quiet, 1=summary, 2=per-function
}

Stats {
    functions_total: usize
    functions_cached: usize     // Cache hits
    functions_compiled: usize   // Cache misses
}
```

**Implementation:**

```
CachedCodegen.init(air_cache, file_path, verbosity) -> CachedCodegen {
    return CachedCodegen {
        air_cache: air_cache,
        file_path: file_path,
        stats: Stats { 0, 0, 0 },
        verbosity: verbosity,
    }
}

CachedCodegen.generate(self, program) -> string {
    output = []

    for func in program.functions {
        self.stats.functions_total += 1

        // Compute ZIR hash for this function
        zir_hash = hashFunctionZir(func)

        // Try cache first
        cached_ir = self.air_cache.get(
            self.file_path,
            func.name,
            zir_hash
        )

        if cached_ir != null {
            // CACHE HIT!
            self.stats.functions_cached += 1

            if self.verbosity >= 2 {
                print("[func] {}: HIT (hash={:016x})", func.name, zir_hash)
            }

            output.append(cached_ir)
        } else {
            // CACHE MISS - compile
            self.stats.functions_compiled += 1

            if self.verbosity >= 2 {
                print("[func] {}: MISS (hash={:016x}) -> compiling",
                    func.name, zir_hash)
            }

            func_ir = generateSingleFunction(func)

            // Store in cache for next time
            self.air_cache.put(
                self.file_path,
                func.name,
                zir_hash,
                func_ir
            )

            output.append(func_ir)
        }
    }

    if self.verbosity >= 1 {
        print("[codegen] {}: {} total, {} cached, {} compiled",
            self.file_path,
            self.stats.functions_total,
            self.stats.functions_cached,
            self.stats.functions_compiled)
    }

    return join(output, "\n\n")
}
```

**Usage in Compiler:**

```
compileFile(air_cache, file_path, source) -> string {
    // Parse and lower to ZIR
    program = parse_and_lower(source)

    // Use cached codegen
    codegen = CachedCodegen.init(air_cache, file_path, verbosity: 1)
    llvm_ir = codegen.generate(program)

    return llvm_ir
}
```

### Complete Flow Example

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXAMPLE: Compiling math.mini after changing mul()                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ math.mini has: add(), sub(), mul()                                  │
│ You changed: mul() implementation                                   │
│                                                                     │
│ codegen.generate(program):                                          │
│                                                                     │
│ [func] add: HIT (hash=0xaaa111...)    ← Unchanged, use cache        │
│ [func] sub: HIT (hash=0xbbb222...)    ← Unchanged, use cache        │
│ [func] mul: MISS (hash=0xccc333...)   ← Changed, recompile          │
│                                                                     │
│ [codegen] math.mini: 3 total, 2 cached, 1 compiled                  │
│                                                                     │
│ Only 1/3 functions compiled = 3x faster for this file!              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Implement `CachedCodegen`
2. Integrate with your compiler
3. Test:

```
// Setup: Pre-populate cache
cache = AirCache.init(".cache")

// Compile once to populate cache
program1 = parse_and_lower("fn add() {} fn sub() {} fn mul() {}")
gen1 = CachedCodegen.init(cache, "math.mini", verbosity: 0)
gen1.generate(program1)

assert gen1.stats.functions_cached == 0   // First time, all misses
assert gen1.stats.functions_compiled == 3

// Compile again (no changes)
program2 = parse_and_lower("fn add() {} fn sub() {} fn mul() {}")
gen2 = CachedCodegen.init(cache, "math.mini", verbosity: 0)
gen2.generate(program2)

assert gen2.stats.functions_cached == 3   // All hits!
assert gen2.stats.functions_compiled == 0

// Compile with one changed function
program3 = parse_and_lower("fn add() {} fn sub() {} fn mul() { return 1; }")
gen3 = CachedCodegen.init(cache, "math.mini", verbosity: 0)
gen3.generate(program3)

assert gen3.stats.functions_cached == 2   // add, sub hit
assert gen3.stats.functions_compiled == 1  // mul recompiled
```

### Benchmark Data

| Scenario | Without Function Cache | With Function Cache |
|----------|----------------------|---------------------|
| 10 functions, all unchanged | 5ms | 1ms |
| 10 functions, 1 changed | 5ms | 1.5ms |
| **Typical file edit** | - | **~3x faster** |

---

## Summary: Complete AirCache

```
┌────────────────────────────────────────────────────────────────────┐
│ AirCache + CachedCodegen - Complete Implementation                 │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ AirCache {                                                         │
│     cache_dir: string                                              │
│     objects_dir: string                                            │
│     index: Map<string, u64>     // "path:func" → zir_hash          │
│ }                                                                  │
│                                                                    │
│ Methods:                                                           │
│     init(cache_dir)                                                │
│     get(file_path, func_name, zir_hash) -> string | null           │
│     put(file_path, func_name, zir_hash, llvm_ir)                   │
│     load() / save()             // Persist index                   │
│                                                                    │
│ CachedCodegen {                                                    │
│     air_cache: *AirCache                                           │
│     file_path: string                                              │
│     stats: Stats                                                   │
│ }                                                                  │
│                                                                    │
│ Methods:                                                           │
│     init(air_cache, file_path, verbosity)                          │
│     generate(program) -> string  // Uses cache automatically       │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**When Function Cache Helps:**

| Scenario | Benefit |
|----------|---------|
| Large files with many functions | High - only recompile changed ones |
| Small files (1-2 functions) | Low - file-level cache is sufficient |
| Comment/whitespace changes | High - ZIR hash unchanged |
| Major refactoring | Low - most functions change |

---

## Next Steps

You now have multi-level caching:
- **FileHashCache** - Detect which files changed
- **ZirCache** - Skip unchanged files entirely
- **AirCache** - Skip unchanged functions within changed files

Next, let's see how to combine these caches efficiently.

**Next: [Module 4: Multi-Level Integration](../04-multi-level-cache/)** - Combine all caches

---

## Complete Code Reference

For a complete implementation, see:
- `src/cache.zig` - `AirCache` and `CachedCodegen` structs

Key functions:
- `hashFunctionZir()` - ZIR-based function hashing
- `AirCache.get()` / `put()` - Content-addressed storage
- `CachedCodegen.generate()` - Transparent cache wrapper
