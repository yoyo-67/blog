---
title: "Zig Compiler Internals Part 1: The Bootstrap Process"
---

# Zig Compiler Internals Part 1: The Bootstrap Process

*How Zig builds itself from nothing but a C compiler*

---

## Introduction

One of the most fascinating aspects of the Zig programming language is how it compiles itself. Zig is a **self-hosted** compiler, meaning the Zig compiler is written in Zig. But this creates a chicken-and-egg problem: how do you compile the Zig compiler if you don't have a Zig compiler yet?

The answer is Zig's elegant **multi-stage bootstrap process**. In this article, we'll dive deep into how Zig solves this problem using only a C99 compiler as the starting point.

## The Chicken-and-Egg Problem

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    THE SELF-HOSTING PARADOX                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│    Zig Compiler                              Zig Compiler                    │
│    (written in Zig)  ─────────────────────▶  (executable)                   │
│          │                                         ▲                         │
│          │                                         │                         │
│          │              NEEDS                      │                         │
│          └─────────────────────────────────────────┘                         │
│                                                                              │
│    🐔 To compile Zig code, you need a Zig compiler                          │
│    🥚 To get a Zig compiler, you need to compile Zig code                   │
│                                                                              │
│    HOW DO YOU START?                                                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

The solution: use a **different language** to break the cycle. Zig uses C as the escape hatch.

## The Bootstrap Stages - Big Picture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ZIG BOOTSTRAP OVERVIEW                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  STAGE 0: Pure C (uses system C compiler)                                   │
│  ════════════════════════════════════════                                   │
│                                                                              │
│    ┌──────────────┐         ┌──────────────┐         ┌──────────────┐       │
│    │ bootstrap.c  │   cc    │  zig-wasm2c  │  wasm2c │   zig1.c     │       │
│    │ wasm2c.c     │ ──────▶ │  executable  │ ──────▶ │ (huge file)  │       │
│    └──────────────┘         └──────────────┘         └──────────────┘       │
│                                    │                        │                │
│                                    ▼                        │                │
│    ┌──────────────┐         ┌──────────────┐               │                │
│    │ zig1.wasm    │ ───────▶│   convert    │◀──────────────┘                │
│    │ (3MB binary) │         │   wasm→C     │                                │
│    └──────────────┘         └──────────────┘                                │
│                                    │                                         │
│                                    ▼                                         │
│    ┌──────────────┐   cc    ┌──────────────┐                                │
│    │ zig1.c       │ ──────▶ │    zig1      │  ◀── First Zig compiler!       │
│    │ wasi.c       │         │  executable  │                                │
│    └──────────────┘         └──────────────┘                                │
│                                    │                                         │
│  ══════════════════════════════════╪════════════════════════════════════    │
│                                    │                                         │
│  STAGE 1: Use zig1 to compile Zig to C                                      │
│  ═════════════════════════════════════                                      │
│                                    │                                         │
│                                    ▼                                         │
│    ┌──────────────┐  zig1   ┌──────────────┐                                │
│    │ src/main.zig │ ──────▶ │   zig2.c     │  Zig compiler as C code        │
│    │ (Zig source) │-ofmt=c  │              │                                │
│    └──────────────┘         └──────────────┘                                │
│                                    │                                         │
│    ┌──────────────┐  zig1   ┌──────────────┐                                │
│    │compiler_rt   │ ──────▶ │compiler_rt.c │                                │
│    │    .zig      │-ofmt=c  │              │                                │
│    └──────────────┘         └──────────────┘                                │
│                                    │                                         │
│                                    ▼                                         │
│    ┌──────────────┐   cc    ┌──────────────┐                                │
│    │ zig2.c       │ ──────▶ │    zig2      │  ◀── Full Zig compiler!        │
│    │compiler_rt.c │         │  executable  │                                │
│    └──────────────┘         └──────────────┘                                │
│                                    │                                         │
│  ══════════════════════════════════╪════════════════════════════════════    │
│                                    │                                         │
│  STAGE 2+: Self-hosted compilation                                          │
│  ═════════════════════════════════                                          │
│                                    │                                         │
│                                    ▼                                         │
│    ┌──────────────┐  zig2   ┌──────────────┐                                │
│    │ src/main.zig │ ──────▶ │    zig3      │  ◀── Production compiler       │
│    │ (Zig source) │  build  │  (stage 3)   │      (with LLVM, optimized)    │
│    └──────────────┘         └──────────────┘                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## The Key Insight: WebAssembly as a Universal Binary

Why WebAssembly? Here's the genius:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    WHY WEBASSEMBLY FOR BOOTSTRAP?                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Traditional Bootstrap Problem:                                              │
│  ─────────────────────────────                                               │
│                                                                              │
│    Linux x86_64 ──▶ Needs x86_64 bootstrap binary                           │
│    Linux ARM64  ──▶ Needs ARM64 bootstrap binary                            │
│    macOS x86_64 ──▶ Needs macOS x86_64 bootstrap binary                     │
│    macOS ARM64  ──▶ Needs macOS ARM64 bootstrap binary                      │
│    Windows      ──▶ Needs Windows bootstrap binary                          │
│    FreeBSD      ──▶ Needs FreeBSD bootstrap binary                          │
│    ...and many more!                                                         │
│                                                                              │
│    Problem: Need to maintain N different bootstrap binaries!                 │
│                                                                              │
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                              │
│  Zig's Solution with WebAssembly:                                            │
│  ────────────────────────────────                                            │
│                                                                              │
│                         ┌─────────────────┐                                  │
│                         │   zig1.wasm     │                                  │
│                         │   (ONE file)    │                                  │
│                         │   ~3MB          │                                  │
│                         └────────┬────────┘                                  │
│                                  │                                           │
│                          wasm2c (transpile)                                  │
│                                  │                                           │
│                                  ▼                                           │
│                         ┌─────────────────┐                                  │
│                         │    zig1.c       │                                  │
│                         │  (portable C)   │                                  │
│                         └────────┬────────┘                                  │
│                                  │                                           │
│              ┌───────────────────┼───────────────────┐                       │
│              │                   │                   │                       │
│              ▼                   ▼                   ▼                       │
│    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐              │
│    │  Linux x86_64   │ │  macOS ARM64    │ │    Windows      │              │
│    │     zig1        │ │     zig1        │ │     zig1        │              │
│    └─────────────────┘ └─────────────────┘ └─────────────────┘              │
│                                                                              │
│    ✓ ONE wasm file works EVERYWHERE with a C compiler!                       │
│    ✓ Deterministic: same wasm → same C → same behavior                       │
│    ✓ Verifiable: binary is in the git repo                                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Stage 0: The C Bootstrap (`bootstrap.c`)

**Location**: `bootstrap.c` (200 lines)

This tiny C file orchestrates the entire bootstrap. Let's examine it step by step.

### The Entry Point

```c
int main(int argc, char **argv) {
    const char *cc = get_c_compiler();       // Uses $CC or defaults to "cc"
    const char *host_triple = get_host_triple();  // e.g., "x86_64-linux"

    // Step 1: Build the wasm2c tool
    // Step 2: Convert zig1.wasm to C
    // Step 3: Compile zig1
    // Step 4: Generate config.zig
    // Step 5: Use zig1 to compile zig2.c
    // Step 6: Build compiler_rt
    // Step 7: Compile final zig2
}
```

### Host Detection (Actual Source Code)

The bootstrap needs to know what platform it's running on:

```c
static const char *get_host_os(void) {
    const char *host_os = getenv("ZIG_HOST_TARGET_OS");
    if (host_os != NULL) return host_os;
#if defined(__WIN32__)
    return "windows";
#elif defined(__APPLE__)
    return "macos";
#elif defined(__linux__)
    return "linux";
#elif defined(__FreeBSD__)
    return "freebsd";
#elif defined(__DragonFly__)
    return "dragonfly";
#elif defined(__HAIKU__)
    return "haiku";
#else
    panic("unknown host os, specify with ZIG_HOST_TARGET_OS");
#endif
}

static const char *get_host_arch(void) {
    const char *host_arch = getenv("ZIG_HOST_TARGET_ARCH");
    if (host_arch != NULL) return host_arch;
#if defined(__x86_64__)
    return "x86_64";
#elif defined(__aarch64__)
    return "aarch64";
#else
    panic("unknown host arch, specify with ZIG_HOST_TARGET_ARCH");
#endif
}

static const char *get_host_triple(void) {
    const char *host_triple = getenv("ZIG_HOST_TARGET_TRIPLE");
    if (host_triple != NULL) return host_triple;
    static char global_buffer[100];
    sprintf(global_buffer, "%s-%s%s", get_host_arch(), get_host_os(), get_host_abi());
    return global_buffer;
}
```

### Process Execution Helper

The bootstrap runs several child processes:

```c
static void run(char **argv) {
    pid_t pid = fork();
    if (pid == -1)
        panic("fork failed");
    if (pid == 0) {
        // child process
        execvp(argv[0], argv);
        exit(1);
    }

    // parent waits for child
    int status;
    waitpid(pid, &status, 0);

    if (!WIFEXITED(status))
        panic("child process crashed");

    if (WEXITSTATUS(status) != 0)
        panic("child process failed");
}

static void print_and_run(const char **argv) {
    // Print command for visibility
    fprintf(stderr, "%s", argv[0]);
    for (const char **arg = argv + 1; *arg; arg += 1) {
        fprintf(stderr, " %s", *arg);
    }
    fprintf(stderr, "\n");
    run((char **)argv);
}
```

### Step 1: Build the WebAssembly-to-C Transpiler

```c
{
    const char *child_argv[] = {
        cc, "-o", "zig-wasm2c", "stage1/wasm2c.c", "-O2", "-std=c99", NULL,
    };
    print_and_run(child_argv);
}
```

This compiles the `wasm2c` tool, which can read WebAssembly binary format and output equivalent C code.

### Step 2: Convert zig1.wasm to C

```c
{
    const char *child_argv[] = {
        "./zig-wasm2c", "stage1/zig1.wasm", "zig1.c", NULL,
    };
    print_and_run(child_argv);
}
```

This produces `zig1.c` - a massive C file containing the entire Zig compiler!

### Step 3: Compile zig1

```c
{
    const char *child_argv[] = {
        cc, "-o", "zig1", "zig1.c", "stage1/wasi.c", "-std=c99", "-Os", "-lm", NULL,
    };
    print_and_run(child_argv);
}
```

Note the inclusion of `wasi.c` - this provides the system interface that the WebAssembly code expects.

### Step 4: Generate Build Configuration

```c
{
    FILE *f = fopen("config.zig", "wb");
    if (f == NULL)
        panic("unable to open config.zig for writing");

    const char *zig_version = "0.14.0-dev.bootstrap";

    int written = fprintf(f,
        "pub const have_llvm = false;\n"
        "pub const llvm_has_m68k = false;\n"
        "pub const llvm_has_csky = false;\n"
        "pub const llvm_has_arc = false;\n"
        "pub const llvm_has_xtensa = false;\n"
        "pub const version: [:0]const u8 = \"%s\";\n"
        "pub const semver = @import(\"std\").SemanticVersion.parse(version) catch unreachable;\n"
        "pub const enable_debug_extensions = false;\n"
        "pub const enable_logging = false;\n"
        "pub const enable_link_snapshots = false;\n"
        "pub const enable_tracy = false;\n"
        "pub const value_tracing = false;\n"
        "pub const skip_non_native = false;\n"
        "pub const debug_gpa = false;\n"
        "pub const dev = .core;\n"
        "pub const value_interpret_mode = .direct;\n"
    , zig_version);

    if (written < 100)
        panic("unable to write to config.zig file");
    if (fclose(f) != 0)
        panic("unable to finish writing to config.zig file");
}
```

This creates a minimal configuration that disables LLVM and other optional features.

### Step 5: Build zig2 Using zig1

Here's where the magic happens - we use zig1 to compile the FULL Zig compiler source:

```c
{
    const char *child_argv[] = {
        "./zig1", "lib", "build-exe",
        "-ofmt=c",              // Output C code (not machine code!)
        "-lc",                  // Link libc
        "-OReleaseSmall",       // Optimize for size
        "--name", "zig2",
        "-femit-bin=zig2.c",    // Output to zig2.c
        "-target", host_triple,
        "--dep", "build_options",
        "--dep", "aro",
        "-Mroot=src/main.zig",
        "-Mbuild_options=config.zig",
        "-Maro=lib/compiler/aro/aro.zig",
        NULL,
    };
    print_and_run(child_argv);
}
```

The crucial flag here is `-ofmt=c` which tells Zig to output C code instead of machine code.

### Step 6: Build compiler_rt

The compiler runtime library is also compiled to C:

```c
{
    const char *child_argv[] = {
        "./zig1", "lib", "build-obj",
        "-ofmt=c", "-OReleaseSmall",
        "--name", "compiler_rt", "-femit-bin=compiler_rt.c",
        "-target", host_triple,
        "-Mroot=lib/compiler_rt.zig",
        NULL,
    };
    print_and_run(child_argv);
}
```

### Step 7: Compile zig2 to Native Code

Finally, we compile the generated C code to produce a native executable:

```c
{
    const char *child_argv[] = {
        cc, "-o", "zig2", "zig2.c", "compiler_rt.c",
        "-std=c99", "-O2", "-fno-stack-protector",
        "-Istage1",
#if defined(__APPLE__)
        "-Wl,-stack_size,0x10000000",   // 256MB stack for macOS
#else
        "-Wl,-z,stack-size=0x10000000", // 256MB stack for Linux
#endif
#if defined(__GNUC__)
        "-pthread",
#endif
        NULL,
    };
    print_and_run(child_argv);
}
```

At this point, `zig2` is a fully functional Zig compiler!

## The WebAssembly-to-C Transpiler (`wasm2c.c`)

**Location**: `stage1/wasm2c.c` (2,299 lines)

This is a sophisticated transpiler that converts WebAssembly bytecode to equivalent C code.

### Understanding WebAssembly Binary Format

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    WEBASSEMBLY BINARY FORMAT                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         WASM FILE HEADER                               │ │
│  ├────────────────────────────────────────────────────────────────────────┤ │
│  │  Magic Number: 0x00 0x61 0x73 0x6D  ("\0asm")                          │ │
│  │  Version:      0x01 0x00 0x00 0x00  (version 1)                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         SECTIONS                                       │ │
│  ├────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                        │ │
│  │   Section ID │ Name       │ Contents                                  │ │
│  │   ──────────┼────────────┼──────────────────────────────────────────  │ │
│  │      1      │ Type       │ Function type signatures                   │ │
│  │      2      │ Import     │ Imported functions, tables, memories       │ │
│  │      3      │ Function   │ Function declarations (type indices)       │ │
│  │      4      │ Table      │ Table declarations                         │ │
│  │      5      │ Memory     │ Linear memory declarations                 │ │
│  │      6      │ Global     │ Global variable declarations               │ │
│  │      7      │ Export     │ Exported functions, tables, memories       │ │
│  │      8      │ Start      │ Start function index (optional)            │ │
│  │      9      │ Element    │ Table element initializers                 │ │
│  │     10      │ Code       │ Function bodies (the actual code!)         │ │
│  │     11      │ Data       │ Data segment initializers                  │ │
│  │     12      │ DataCount  │ Number of data segments                    │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### WebAssembly Section IDs (from `wasm.h`)

```c
enum WasmSectionId {
    WasmSectionId_type      =  1,   // Function signatures
    WasmSectionId_import    =  2,   // Imported functions
    WasmSectionId_func      =  3,   // Function declarations
    WasmSectionId_table     =  4,   // Function tables
    WasmSectionId_mem       =  5,   // Memory declarations
    WasmSectionId_global    =  6,   // Global variables
    WasmSectionId_export    =  7,   // Exported functions
    WasmSectionId_start     =  8,   // Entry point
    WasmSectionId_elem      =  9,   // Table initializers
    WasmSectionId_code      = 10,   // Function bodies
    WasmSectionId_data      = 11,   // Data segments
    WasmSectionId_datacount = 12,   // Data count
};
```

### WebAssembly Value Types

WebAssembly has a simple type system that maps cleanly to C:

```c
enum WasmValType {
    WasmValType_i32       = -0x01,   // 32-bit integer
    WasmValType_i64       = -0x02,   // 64-bit integer
    WasmValType_f32       = -0x03,   // 32-bit float
    WasmValType_f64       = -0x04,   // 64-bit float
    WasmValType_v128      = -0x05,   // 128-bit vector (SIMD)
    WasmValType_funcref   = -0x10,   // Function reference
    WasmValType_externref = -0x11,   // External reference
    WasmValType_empty     = -0x40,   // Void/empty
};

// How wasm2c converts types to C:
static const char *WasmValType_toC(enum WasmValType val_type) {
    switch (val_type) {
        case WasmValType_i32: return "uint32_t";
        case WasmValType_i64: return "uint64_t";
        case WasmValType_f32: return "float";
        case WasmValType_f64: return "double";
        case WasmValType_funcref: return "void (*)(void)";
        case WasmValType_externref: return "void *";
        default: panic("unsupported value type");
    }
    return NULL;
}
```

### WebAssembly Opcodes

WebAssembly has ~200 instructions. Here are the key ones:

```c
enum WasmOpcode {
    // Control flow
    WasmOpcode_unreachable         = 0x00,  // Trap
    WasmOpcode_nop                 = 0x01,  // No operation
    WasmOpcode_block               = 0x02,  // Begin block
    WasmOpcode_loop                = 0x03,  // Begin loop
    WasmOpcode_if                  = 0x04,  // Begin if
    WasmOpcode_else                = 0x05,  // Begin else
    WasmOpcode_end                 = 0x0B,  // End block/loop/if
    WasmOpcode_br                  = 0x0C,  // Branch
    WasmOpcode_br_if               = 0x0D,  // Conditional branch
    WasmOpcode_br_table            = 0x0E,  // Branch table (switch)
    WasmOpcode_return              = 0x0F,  // Return from function
    WasmOpcode_call                = 0x10,  // Call function
    WasmOpcode_call_indirect       = 0x11,  // Indirect call

    // Variable access
    WasmOpcode_local_get           = 0x20,  // Get local variable
    WasmOpcode_local_set           = 0x21,  // Set local variable
    WasmOpcode_local_tee           = 0x22,  // Tee (get and set)
    WasmOpcode_global_get          = 0x23,  // Get global variable
    WasmOpcode_global_set          = 0x24,  // Set global variable

    // Memory operations
    WasmOpcode_i32_load            = 0x28,  // Load i32 from memory
    WasmOpcode_i64_load            = 0x29,  // Load i64 from memory
    WasmOpcode_f32_load            = 0x2A,  // Load f32 from memory
    WasmOpcode_f64_load            = 0x2B,  // Load f64 from memory
    WasmOpcode_i32_store           = 0x36,  // Store i32 to memory
    WasmOpcode_i64_store           = 0x37,  // Store i64 to memory
    WasmOpcode_memory_grow         = 0x40,  // Grow memory

    // Constants
    WasmOpcode_i32_const           = 0x41,  // Push i32 constant
    WasmOpcode_i64_const           = 0x42,  // Push i64 constant
    WasmOpcode_f32_const           = 0x43,  // Push f32 constant
    WasmOpcode_f64_const           = 0x44,  // Push f64 constant

    // Arithmetic (i32)
    WasmOpcode_i32_add             = 0x6A,  // i32 addition
    WasmOpcode_i32_sub             = 0x6B,  // i32 subtraction
    WasmOpcode_i32_mul             = 0x6C,  // i32 multiplication
    WasmOpcode_i32_div_s           = 0x6D,  // i32 signed division
    WasmOpcode_i32_div_u           = 0x6E,  // i32 unsigned division
    WasmOpcode_i32_and             = 0x71,  // i32 bitwise AND
    WasmOpcode_i32_or              = 0x72,  // i32 bitwise OR
    WasmOpcode_i32_xor             = 0x73,  // i32 bitwise XOR
    WasmOpcode_i32_shl             = 0x74,  // i32 shift left
    WasmOpcode_i32_shr_s           = 0x75,  // i32 signed shift right
    WasmOpcode_i32_shr_u           = 0x76,  // i32 unsigned shift right

    // Comparisons
    WasmOpcode_i32_eqz             = 0x45,  // i32 equals zero
    WasmOpcode_i32_eq              = 0x46,  // i32 equals
    WasmOpcode_i32_ne              = 0x47,  // i32 not equals
    WasmOpcode_i32_lt_s            = 0x48,  // i32 less than (signed)
    WasmOpcode_i32_lt_u            = 0x49,  // i32 less than (unsigned)
    WasmOpcode_i32_gt_s            = 0x4A,  // i32 greater than (signed)
    WasmOpcode_i32_gt_u            = 0x4B,  // i32 greater than (unsigned)

    // ...and many more for i64, f32, f64
};
```

### How wasm2c Generates C Code

The transpiler maintains a virtual stack and generates C code for each instruction:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    WASM2C TRANSPILATION PROCESS                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  WebAssembly Stack Machine           Equivalent C Code                       │
│  ─────────────────────────           ─────────────────                       │
│                                                                              │
│  i32.const 10                        uint32_t l0 = UINT32_C(10);            │
│  i32.const 20                        uint32_t l1 = UINT32_C(20);            │
│  i32.add                             uint32_t l2 = l0 + l1;                 │
│  local.set 0                         l3 = l2;                               │
│                                                                              │
│  ───────────────────────────────────────────────────────────────────────    │
│                                                                              │
│  Stack Evolution:                    Generated Variables:                    │
│                                                                              │
│  i32.const 10:  [10]                 l0 = 10                                │
│  i32.const 20:  [10, 20]             l0 = 10, l1 = 20                       │
│  i32.add:       [30]                 l0 = 10, l1 = 20, l2 = l0+l1           │
│  local.set 0:   []                   local_0 = l2                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Generated Helper Functions

The output begins with portable helper functions:

```c
// Byte swapping for endianness handling
static uint16_t i16_byteswap(uint16_t src) {
    return (uint16_t)(uint8_t)(src >> 0) << 8 |
           (uint16_t)(uint8_t)(src >> 8) << 0;
}
static uint32_t i32_byteswap(uint32_t src) {
    return (uint32_t)i16_byteswap(src >>  0) << 16 |
           (uint32_t)i16_byteswap(src >> 16) <<  0;
}
static uint64_t i64_byteswap(uint64_t src) {
    return (uint64_t)i32_byteswap(src >>  0) << 32 |
           (uint64_t)i32_byteswap(src >> 32) <<  0;
}

// Memory load functions (handle alignment)
uint32_t load32_align0(const uint8_t *ptr) {
    uint32_t val;
    memcpy(&val, ptr, sizeof(val));
    return val;  // byte swap added if big-endian
}

// Memory store functions
void store32_align2(uint32_t *ptr, uint32_t val) {
    memcpy(ptr, &val, sizeof(val));
}

// Bit manipulation (WebAssembly intrinsics)
static uint32_t i32_popcnt(uint32_t lhs) {
    lhs = lhs - ((lhs >> 1) & UINT32_C(0x55555555));
    lhs = (lhs & UINT32_C(0x33333333)) + ((lhs >> 2) & UINT32_C(0x33333333));
    lhs = (lhs + (lhs >> 4)) & UINT32_C(0x0F0F0F0F);
    return (lhs * UINT32_C(0x01010101)) >> 24;
}
static uint32_t i32_ctz(uint32_t lhs) {
    return i32_popcnt(~lhs & (lhs - 1));
}
static uint32_t i32_clz(uint32_t lhs) {
    lhs = i32_byteswap(lhs);
    lhs = (lhs & UINT32_C(0x0F0F0F0F)) << 4 | (lhs & UINT32_C(0xF0F0F0F0)) >> 4;
    lhs = (lhs & UINT32_C(0x33333333)) << 2 | (lhs & UINT32_C(0xCCCCCCCC)) >> 2;
    lhs = (lhs & UINT32_C(0x55555555)) << 1 | (lhs & UINT32_C(0xAAAAAAAA)) >> 1;
    return i32_ctz(lhs);
}

// Memory growth (dynamic allocation)
static uint32_t memory_grow(uint8_t **m, uint32_t *p, uint32_t *c, uint32_t n) {
    uint32_t r = *p;
    uint32_t new_p = r + n;
    if (new_p > UINT32_C(0xFFFF)) return UINT32_C(0xFFFFFFFF);
    uint8_t *new_m = *m;
    uint32_t new_c = *c;
    if (new_c < new_p) {
        do new_c += new_c / 2 + 8; while (new_c < new_p);
        if (new_c > UINT32_C(0xFFFF)) new_c = UINT32_C(0xFFFF);
        new_m = realloc(new_m, new_c << 16);
        if (new_m == NULL) return UINT32_C(0xFFFFFFFF);
        *m = new_m;
        *c = new_c;
    }
    *p = new_p;
    memset(&new_m[r << 16], 0, n << 16);
    return r;
}
```

### Function Generation

For each WebAssembly function, wasm2c generates a C function:

```c
// Example: A WebAssembly function with signature (i32, i32) -> i32
static uint32_t f42(uint32_t l0, uint32_t l1) {
    uint32_t l2;    // local variable
    uint32_t l3;    // stack slot
    uint32_t l4;    // stack slot

    // Function body (generated from opcodes)
    l3 = l0;                            // local.get 0
    l4 = l1;                            // local.get 1
    l2 = l3 + l4;                       // i32.add
    return l2;                          // return
}
```

## WASI: The System Interface (`wasi.c`)

**Location**: `stage1/wasi.c` (1,064 lines)

WASI (WebAssembly System Interface) provides system calls for the WebAssembly code. It's like a minimal operating system layer.

### WASI Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WASI ARCHITECTURE                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                     WASM CODE (zig1.wasm)                               ││
│  │                                                                         ││
│  │   wants to: read files, write output, get args, allocate memory         ││
│  │                                                                         ││
│  └───────────────────────────────────┬─────────────────────────────────────┘│
│                                      │                                       │
│                         WASI function calls                                  │
│                                      │                                       │
│                                      ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                     WASI IMPLEMENTATION (wasi.c)                        ││
│  │                                                                         ││
│  │   fd_read()      - Read from file descriptors                           ││
│  │   fd_write()     - Write to file descriptors                            ││
│  │   fd_seek()      - Seek in files                                        ││
│  │   fd_close()     - Close file descriptors                               ││
│  │   path_open()    - Open files by path                                   ││
│  │   args_get()     - Get command line arguments                           ││
│  │   clock_time_get()- Get current time                                    ││
│  │   random_get()   - Get random bytes                                     ││
│  │   proc_exit()    - Exit process                                         ││
│  │                                                                         ││
│  └───────────────────────────────────┬─────────────────────────────────────┘│
│                                      │                                       │
│                        Native system calls                                   │
│                                      │                                       │
│                                      ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                     HOST OPERATING SYSTEM                               ││
│  │                                                                         ││
│  │   Linux / macOS / Windows / FreeBSD / etc.                              ││
│  │                                                                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### WASI Error Codes

```c
enum wasi_errno {
    wasi_errno_success        = 0,   // Success
    wasi_errno_2big           = 1,   // Argument list too long
    wasi_errno_acces          = 2,   // Permission denied
    wasi_errno_badf           = 8,   // Bad file descriptor
    wasi_errno_exist          = 20,  // File exists
    wasi_errno_inval          = 28,  // Invalid argument
    wasi_errno_io             = 29,  // I/O error
    wasi_errno_isdir          = 31,  // Is a directory
    wasi_errno_noent          = 44,  // No such file or directory
    wasi_errno_nomem          = 48,  // Out of memory
    wasi_errno_notdir         = 54,  // Not a directory
    // ... and many more
};
```

### File Descriptor Management

WASI maintains a table of open file descriptors:

```c
static uint32_t fd_len;
static struct FileDescriptor {
    uint32_t de;                      // Directory entry index
    enum wasi_fdflags fdflags;        // Flags (append, sync, etc.)
    FILE *stream;                     // Underlying C FILE*
    uint64_t fs_rights_inheriting;    // Capability rights
} *fds;

// Standard file descriptors are pre-opened:
// fd 0 = stdin
// fd 1 = stdout
// fd 2 = stderr
// fd 3+ = user-opened files
```

### Key WASI Functions

#### Reading Files

```c
uint32_t wasi_snapshot_preview1_fd_read(
    uint32_t fd,
    uint32_t iovs,         // Scatter-gather buffers
    uint32_t iovs_len,
    uint32_t res_size      // Output: bytes read
) {
    uint8_t *const m = *wasm_memory;
    struct wasi_ciovec *iovs_ptr = (struct wasi_ciovec *)&m[iovs];
    uint32_t *res_size_ptr = (uint32_t *)&m[res_size];

    if (fd >= fd_len || fds[fd].de >= de_len) return wasi_errno_badf;

    if (fds[fd].stream == NULL) {
        store32_align2(res_size_ptr, 0);
        return wasi_errno_success;
    }

    size_t size = 0;
    for (uint32_t i = 0; i < iovs_len; i += 1) {
        uint32_t len = load32_align2(&iovs_ptr[i].len);
        size_t read_size = fread(
            &m[load32_align2(&iovs_ptr[i].ptr)],
            1, len,
            fds[fd].stream
        );
        size += read_size;
        if (read_size < len) break;
    }

    store32_align2(res_size_ptr, size);
    return wasi_errno_success;
}
```

#### Writing Files

```c
uint32_t wasi_snapshot_preview1_fd_write(
    uint32_t fd,
    uint32_t iovs,
    uint32_t iovs_len,
    uint32_t res_size
) {
    uint8_t *const m = *wasm_memory;
    struct wasi_ciovec *iovs_ptr = (struct wasi_ciovec *)&m[iovs];
    uint32_t *res_size_ptr = (uint32_t *)&m[res_size];

    if (fd >= fd_len || fds[fd].de >= de_len) return wasi_errno_badf;

    size_t size = 0;
    for (uint32_t i = 0; i < iovs_len; i += 1) {
        uint32_t len = load32_align2(&iovs_ptr[i].len);
        size_t written_size = 0;
        if (fds[fd].stream != NULL)
            written_size = fwrite(
                &m[load32_align2(&iovs_ptr[i].ptr)],
                1, len,
                fds[fd].stream
            );
        else
            written_size = len;
        size += written_size;
        if (written_size < len) break;
    }

    store32_align2(res_size_ptr, size);
    return wasi_errno_success;
}
```

#### Getting Command Line Arguments

```c
uint32_t wasi_snapshot_preview1_args_get(uint32_t argv, uint32_t argv_buf) {
    uint8_t *const m = *wasm_memory;
    uint32_t *argv_ptr = (uint32_t *)&m[argv];
    char *argv_buf_ptr = (char *)&m[argv_buf];

    int c_argc = global_argc;
    char **c_argv = global_argv;
    uint32_t dst_i = 0;
    uint32_t argv_buf_i = 0;

    for (int src_i = 0; src_i < c_argc; src_i += 1) {
        if (src_i == 1) continue;  // Skip lib path argument
        store32_align2(&argv_ptr[dst_i], argv_buf + argv_buf_i);
        dst_i += 1;
        strcpy(&argv_buf_ptr[argv_buf_i], c_argv[src_i]);
        argv_buf_i += strlen(c_argv[src_i]) + 1;
    }
    return wasi_errno_success;
}
```

#### Process Exit

```c
void wasi_snapshot_preview1_proc_exit(uint32_t rval) {
    exit(rval);
}
```

#### Getting Random Bytes

```c
uint32_t wasi_snapshot_preview1_random_get(uint32_t buf, uint32_t buf_len) {
    uint8_t *const m = *wasm_memory;
    uint8_t *buf_ptr = (uint8_t *)&m[buf];

    for (uint32_t i = 0; i < buf_len; i += 1)
        buf_ptr[i] = (uint8_t)rand();

    return wasi_errno_success;
}
```

#### Getting Time

```c
uint32_t wasi_snapshot_preview1_clock_time_get(
    uint32_t id,
    uint64_t precision,
    uint32_t res_timestamp
) {
    uint8_t *const m = *wasm_memory;
    uint64_t *res_timestamp_ptr = (uint64_t *)&m[res_timestamp];

    switch (id) {
        case wasi_clockid_realtime:
            // Return nanoseconds since Unix epoch
            store64_align3(res_timestamp_ptr, time(NULL) * UINT64_C(1000000000));
            break;
        case wasi_clockid_monotonic:
        case wasi_clockid_process_cputime_id:
        case wasi_clockid_thread_cputime_id:
            // Return process CPU time in nanoseconds
            store64_align3(res_timestamp_ptr,
                clock() * (UINT64_C(1000000000) / CLOCKS_PER_SEC));
            break;
        default:
            return wasi_errno_inval;
    }
    return wasi_errno_success;
}
```

## The C Backend: How Zig Outputs C

When zig1 runs with `-ofmt=c`, it uses Zig's C backend to generate portable C code. This is a critical feature that enables the bootstrap.

### Example Transformation

Given Zig code:

```zig
pub fn add(a: u32, b: u32) u32 {
    return a + b;
}
```

The C backend generates:

```c
static uint32_t zig_add(uint32_t const a, uint32_t const b) {
    uint32_t zig_tmp_0;
    zig_tmp_0 = a + b;
    return zig_tmp_0;
}
```

### Why C Output?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    WHY C AS AN INTERMEDIATE FORMAT?                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. UNIVERSALITY                                                             │
│     ─────────────                                                            │
│     C compilers exist for EVERY platform                                     │
│     No need for LLVM or custom backends                                      │
│                                                                              │
│  2. PORTABILITY                                                              │
│     ───────────                                                              │
│     Generated C is standard C99                                              │
│     Works with gcc, clang, MSVC, tcc, etc.                                  │
│                                                                              │
│  3. VERIFIABILITY                                                            │
│     ─────────────                                                            │
│     Generated C is human-readable                                            │
│     Can inspect exactly what Zig compiles to                                │
│                                                                              │
│  4. DEBUGGING                                                                │
│     ─────────                                                                │
│     Can debug the generated C with standard tools                            │
│     Easier to diagnose codegen issues                                        │
│                                                                              │
│  5. BOOTSTRAP                                                                │
│     ─────────                                                                │
│     Breaks the circular dependency                                           │
│     Zig can compile itself to C, then C compiler builds it                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Complete Bootstrap Timeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    COMPLETE BOOTSTRAP TIMELINE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  TIME         ACTION                          ARTIFACT                       │
│  ────         ──────                          ────────                       │
│                                                                              │
│  T+0s         Start: run bootstrap.c                                        │
│               │                                                              │
│  T+1s         cc stage1/wasm2c.c ───────────▶ zig-wasm2c                    │
│               │                                                              │
│  T+2s         ./zig-wasm2c zig1.wasm ───────▶ zig1.c                        │
│               │                               (~100MB of C code!)            │
│               │                                                              │
│  T+30s        cc zig1.c wasi.c ─────────────▶ zig1                          │
│               │                               (First Zig compiler!)          │
│               │                                                              │
│  T+31s        Generate config.zig                                            │
│               │                                                              │
│  T+60s        ./zig1 src/main.zig -ofmt=c ──▶ zig2.c                        │
│               │                               (Full compiler as C)           │
│               │                                                              │
│  T+90s        ./zig1 compiler_rt.zig ───────▶ compiler_rt.c                 │
│               │                                                              │
│  T+120s       cc zig2.c compiler_rt.c ──────▶ zig2                          │
│               │                               (Full native compiler!)        │
│               │                                                              │
│  T+121s       Bootstrap complete!                                            │
│               │                                                              │
│  (optional)   ./zig2 build ─────────────────▶ stage3/bin/zig                │
│                                               (Production compiler)          │
│                                                                              │
│  Total time: ~2 minutes on modern hardware                                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Minimal Dependencies

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BOOTSTRAP DEPENDENCIES                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Required:                                                                   │
│  ─────────                                                                   │
│  ✓ C99 compiler (cc, gcc, clang, tcc, etc.)                                 │
│  ✓ Standard C library (libc)                                                 │
│  ✓ Basic POSIX environment (fork, exec, wait)                               │
│                                                                              │
│  NOT Required:                                                               │
│  ──────────────                                                              │
│  ✗ LLVM                                                                      │
│  ✗ CMake                                                                     │
│  ✗ Python                                                                    │
│  ✗ Make                                                                      │
│  ✗ Any specific compiler version                                            │
│  ✗ Internet connection                                                       │
│                                                                              │
│  Result: Can bootstrap on almost any Unix-like system!                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2. Deterministic Builds

The same `zig1.wasm` produces the same results everywhere:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DETERMINISM GUARANTEE                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  zig1.wasm (in git)                                                          │
│       │                                                                      │
│       ▼                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                      │
│  │  Linux x64  │    │   macOS M1  │    │  FreeBSD    │                      │
│  │             │    │             │    │             │                      │
│  │  wasm2c    │    │  wasm2c    │    │  wasm2c    │                      │
│  │     ↓       │    │     ↓       │    │     ↓       │                      │
│  │  zig1.c     │    │  zig1.c     │    │  zig1.c     │                      │
│  │             │    │             │    │             │                      │
│  │  IDENTICAL  │====│  IDENTICAL  │====│  IDENTICAL  │                      │
│  │             │    │             │    │             │                      │
│  └─────────────┘    └─────────────┘    └─────────────┘                      │
│                                                                              │
│  The generated C code is byte-for-byte identical!                            │
│  (Only native compilation introduces platform differences)                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3. Self-Improving Compilation

Each stage produces a more capable compiler:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    COMPILER CAPABILITY PROGRESSION                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Stage      │ Source    │ Backend  │ Speed   │ Features                     │
│  ───────────┼───────────┼──────────┼─────────┼────────────────────────────  │
│  zig1       │ zig1.wasm │ wasm2c   │ Slow    │ Minimal (C output only)      │
│  zig2       │ zig2.c    │ C native │ Medium  │ Full (no LLVM)               │
│  zig3/stage3│ Zig native│ Native   │ Fast    │ Full + LLVM optimizations    │
│                                                                              │
│  Performance improvement: ~100x from zig1 to zig3                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Updating the Bootstrap

When Zig developers make changes to the compiler, they may need to update `zig1.wasm`:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    UPDATING THE BOOTSTRAP                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Developer makes changes to compiler source                               │
│                                                                              │
│  2. Build new compiler with existing stage3:                                 │
│     $ zig build                                                              │
│                                                                              │
│  3. Use new compiler to build WASM version:                                  │
│     $ ./zig-out/bin/zig build \                                             │
│         -Dtarget=wasm32-wasi \                                              │
│         -Doptimize=ReleaseSmall                                             │
│                                                                              │
│  4. Test that bootstrap still works:                                         │
│     $ rm -rf zig1 zig2 zig1.c zig2.c                                        │
│     $ cc bootstrap.c -o bootstrap && ./bootstrap                             │
│                                                                              │
│  5. Replace zig1.wasm in repository:                                         │
│     $ cp zig-out/bin/zig.wasm stage1/zig1.wasm                              │
│                                                                              │
│  6. Commit the new zig1.wasm                                                 │
│                                                                              │
│  This process is called "updating the bootstrap"                             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Historical Context

The bootstrap design evolved over Zig's development:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BOOTSTRAP EVOLUTION                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Era 1: C++ Bootstrap (2015-2020)                                           │
│  ────────────────────────────────                                            │
│  - Original Zig compiler written in C++                                      │
│  - LLVM required for all builds                                              │
│  - Platform support limited by LLVM availability                             │
│                                                                              │
│  Era 2: Self-Hosted Development (2020-2022)                                 │
│  ──────────────────────────────────────────                                  │
│  - Parallel self-hosted compiler development                                 │
│  - C++ version maintained alongside                                          │
│  - Gradual feature parity                                                    │
│                                                                              │
│  Era 3: WebAssembly Bootstrap (2022-present)                                │
│  ───────────────────────────────────────────                                 │
│  - Self-hosted compiler becomes primary                                      │
│  - WebAssembly enables universal bootstrap                                   │
│  - C++ code removed from repository                                          │
│  - LLVM optional (only for optimizations)                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Summary: The Complete Picture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ZIG BOOTSTRAP: THE COMPLETE PICTURE                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                          ┌─────────────────┐                                 │
│                          │   zig1.wasm     │                                 │
│                          │  (in git repo)  │                                 │
│                          └────────┬────────┘                                 │
│                                   │                                          │
│                          wasm2c transpilation                                │
│                                   │                                          │
│                                   ▼                                          │
│                          ┌─────────────────┐                                 │
│                          │     zig1.c      │                                 │
│                          │  (temporary)    │                                 │
│                          └────────┬────────┘                                 │
│                                   │                                          │
│                          C compilation (cc)                                  │
│                                   │                                          │
│                                   ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                           zig1 executable                               ││
│  │                                                                         ││
│  │   • Minimal Zig compiler                                                ││
│  │   • Can only output C code                                              ││
│  │   • Slow but functional                                                 ││
│  │                                                                         ││
│  └────────────────────────────────┬────────────────────────────────────────┘│
│                                   │                                          │
│                          Compile Zig → C                                     │
│                                   │                                          │
│                                   ▼                                          │
│                          ┌─────────────────┐                                 │
│                          │     zig2.c      │                                 │
│                          │  (temporary)    │                                 │
│                          └────────┬────────┘                                 │
│                                   │                                          │
│                          C compilation (cc)                                  │
│                                   │                                          │
│                                   ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                           zig2 executable                               ││
│  │                                                                         ││
│  │   • Full Zig compiler                                                   ││
│  │   • All backends available                                              ││
│  │   • Can self-host                                                       ││
│  │                                                                         ││
│  └────────────────────────────────┬────────────────────────────────────────┘│
│                                   │                                          │
│                          Optional: build stage3                              │
│                                   │                                          │
│                                   ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                       stage3 executable                                 ││
│  │                                                                         ││
│  │   • Production Zig compiler                                             ││
│  │   • LLVM optimizations (optional)                                       ││
│  │   • Full optimizations enabled                                          ││
│  │   • This is what ships to users                                         ││
│  │                                                                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  KEY INSIGHT: Only need a C compiler to build Zig from source!              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Conclusion

Zig's bootstrap process is a masterpiece of practical engineering:

1. **WebAssembly** provides a portable, deterministic binary format
2. **wasm2c** transpiles WebAssembly to portable C99
3. **WASI** provides a minimal system interface
4. **C backend** allows Zig to output C code
5. **Multi-stage bootstrap** progressively builds better compilers

The result: Zig can be built from source on virtually any platform with just a C compiler, no other dependencies required.

In the next article, we'll dive into the first stage of the actual compilation pipeline: the **Tokenizer**, which converts source code into tokens.

---

**Next**: [Part 2: The Tokenizer](./02-tokenizer.md)

**Series Index**:
1. **Bootstrap Process** (this article)
2. [Tokenizer](./02-tokenizer.md)
3. [Parser and AST](./03-parser-ast.md)
4. [ZIR Generation](./04-zir-generation.md)
5. [Semantic Analysis](./05-sema.md)
6. [AIR and Code Generation](./06-air-codegen.md)
7. [Linking](./07-linking.md)

---

## Further Reading

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Source Code](https://github.com/ziglang/zig)
- [WebAssembly Specification](https://webassembly.github.io/spec/)
- [WASI Specification](https://wasi.dev/)
- [LEB128 Encoding](https://en.wikipedia.org/wiki/LEB128) (used in WebAssembly)
