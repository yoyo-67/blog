---
title: "eBPF Observability for Compilers"
weight: 7
---

# Tracing Your Compiler with eBPF

Ever wondered what's happening inside your compiler? Let's add production-grade observability using eBPF - the same technology powering Netflix, Facebook, and Cloudflare's monitoring.

---

## What We'll Build

By the end of this lesson, you'll have:

- **Trace probes** in your compiler that eBPF can attach to
- **bpftrace scripts** to collect cache hit/miss rates and latency histograms
- **Zero-overhead tracing** - no performance impact when not actively tracing
- **Docker setup** to run eBPF on Linux (since macOS doesn't support eBPF)

---

## Why eBPF?

| Approach | Overhead | Production-safe | Rich data |
|----------|----------|-----------------|-----------|
| printf   | High     | No              | Limited   |
| Logging  | Medium   | Yes             | Medium    |
| eBPF     | Near-zero| Yes             | Excellent |

With eBPF, we can:
- Trace function calls without modifying the binary
- Build histograms and aggregations in-kernel
- Collect data only when we need it

---

## The Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Compiler (Zig)          │   eBPF/bpftrace                 │
├─────────────────────────────────────────────────────────────┤
│                          │                                  │
│  cache_hit(name, hash)   │◄──── uprobe:cache_hit           │
│       ↓                  │         │                        │
│  cache_miss(name, hash)  │◄────────┤ aggregate stats       │
│       ↓                  │         │                        │
│  compile_start(name)     │◄────────┤ measure latency       │
│       ↓                  │         │                        │
│  compile_end(name, size) │◄────────┘ output histograms     │
│                          │                                  │
└─────────────────────────────────────────────────────────────┘
```

The compiler exports trace functions that do nothing on their own. eBPF attaches to these functions and reads their arguments directly from CPU registers.

---

## Step 1: Adding Trace Points

Create `src/trace.zig`:

```zig
//! eBPF Tracing Infrastructure
//!
//! Trace points that can be attached via eBPF uprobes.
//! The functions are exported with C ABI so bpftrace can find them.

/// Fired when a function is found in the cache
export fn trace_cache_hit(
    name_ptr: [*]const u8,
    name_len: usize,
    hash: u64
) callconv(.C) void {
    _ = name_ptr; _ = name_len; _ = hash;
    // Empty - just a probe point for eBPF to attach
}

/// Fired when a function is NOT found in cache
export fn trace_cache_miss(
    name_ptr: [*]const u8,
    name_len: usize,
    hash: u64
) callconv(.C) void {
    _ = name_ptr; _ = name_len; _ = hash;
}

/// Fired when compilation starts
export fn trace_compile_start(
    name_ptr: [*]const u8,
    name_len: usize
) callconv(.C) void {
    _ = name_ptr; _ = name_len;
}

/// Fired when compilation ends
export fn trace_compile_end(
    name_ptr: [*]const u8,
    name_len: usize,
    ir_size: usize
) callconv(.C) void {
    _ = name_ptr; _ = name_len; _ = ir_size;
}

// Convenience wrappers for Zig callers
pub fn cacheHit(name: []const u8, hash: u64) void {
    trace_cache_hit(name.ptr, name.len, hash);
}

pub fn cacheMiss(name: []const u8, hash: u64) void {
    trace_cache_miss(name.ptr, name.len, hash);
}
```

Key points:
- Functions are `export` with `callconv(.C)` so they appear as symbols in the binary
- Arguments are intentionally unused - eBPF reads them from registers
- Zero overhead when not tracing

---

## Step 2: Instrumenting the Cache

Add trace calls to `cache.zig`:

```zig
const trace = @import("trace.zig");

// In CachedCodegen.generate():
if (self.air_cache.get(file_path, function.name, zir_hash)) |cached_ir| {
    // Cache hit
    trace.cacheHit(function.name, zir_hash);
    try output.appendSlice(self.allocator, cached_ir);
} else {
    // Cache miss - compile
    trace.cacheMiss(function.name, zir_hash);
    trace.compileStart(function.name);

    var gen = codegen_mod.init(self.allocator);
    const func_ir = try gen.generateSingleFunction(function);

    trace.compileEnd(function.name, func_ir.len);
    // ... cache and continue
}
```

---

## Step 3: The bpftrace Script

Create `tools/trace.bt`:

```c
#!/usr/bin/env bpftrace

BEGIN {
    printf("Tracing compiler cache... Hit Ctrl-C to end.\n\n");
}

// Track cache hits
uprobe:./zig-out/bin/comp:trace_cache_hit {
    @cache_hits++;
    $name = str(arg0, arg1);
    @hit_functions[$name] = count();
}

// Track cache misses
uprobe:./zig-out/bin/comp:trace_cache_miss {
    @cache_misses++;
    $name = str(arg0, arg1);
    @miss_functions[$name] = count();
}

// Measure compilation latency
uprobe:./zig-out/bin/comp:trace_compile_start {
    $name = str(arg0, arg1);
    @compile_start[$name] = nsecs;
}

uprobe:./zig-out/bin/comp:trace_compile_end {
    $name = str(arg0, arg1);
    $duration_us = (nsecs - @compile_start[$name]) / 1000;
    @compile_latency_us = hist($duration_us);
    delete(@compile_start[$name]);

    // Track IR sizes
    @ir_sizes = hist(arg2);
}

END {
    printf("\n=== Cache Statistics ===\n");
    printf("Hits:   %d\n", @cache_hits);
    printf("Misses: %d\n", @cache_misses);
    printf("Hit Rate: %.1f%%\n",
           @cache_hits * 100 / (@cache_hits + @cache_misses));

    printf("\n=== Compilation Latency (us) ===\n");
    print(@compile_latency_us);

    printf("\n=== IR Sizes (bytes) ===\n");
    print(@ir_sizes);
}
```

---

## Step 4: Running It

Since eBPF requires Linux, we use Docker:

```bash
# Build and run
./tools/run-trace.sh

# Or with a specific file
./tools/run-trace.sh my-program.mini
```

The script builds the compiler in a Linux container and runs bpftrace to collect data.

---

## Example Output

```
$ ./tools/run-trace.sh

Tracing compiler cache... Hit Ctrl-C to end.

=== Cache Statistics ===
Hits:   42
Misses: 8
Hit Rate: 84.0%

=== Compilation Latency (us) ===
@compile_latency_us:
[1, 2)               2 |@@@@@@@@                              |
[2, 4)               3 |@@@@@@@@@@@@                          |
[4, 8)               2 |@@@@@@@@                              |
[8, 16)              1 |@@@@                                  |

=== IR Sizes (bytes) ===
@ir_sizes:
[32, 64)             3 |@@@@@@@@@@@@                          |
[64, 128)            4 |@@@@@@@@@@@@@@@@                      |
[128, 256)           1 |@@@@                                  |
```

---

## What We Learned

From this trace:
- **84% cache hit rate** - the incremental cache is working
- **2-8 microseconds** per function compile - very fast
- **64-128 bytes** typical IR size - small functions

---

## Key Takeaways

1. **Export empty functions** - eBPF reads args from registers, not memory
2. **Use C calling convention** - so bpftrace can find symbols
3. **Zero overhead** - trace functions are just NOPs when not attached
4. **Histograms are powerful** - aggregate data in-kernel, not userspace

---

## Try It Yourself

1. Add more trace points (lexer, parser, semantic analysis)
2. Track memory allocations
3. Build flame graphs with `bpftrace -e 'profile:hz:99 { @[ustack] = count(); }'`

---

## Next Steps

Now that we can observe our compiler, we can find and fix performance bottlenecks with confidence.

**[Back to Index](../)** | **[Previous: ARM64 Codegen](../05-codegen-arm64/)**
