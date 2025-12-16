# Zig Compiler Internals Part 6: AIR and Code Generation

*From typed IR to machine code (or C, or LLVM)*

---

## Introduction

After Sema produces typed **AIR** (Analyzed Intermediate Representation), we're finally ready for the last step: generating actual executable code. But this isn't as simple as it sounds!

This article explains:
- What AIR is and why we need it
- How code generation works
- Why Zig has multiple backends (C, LLVM, native)
- How each backend transforms AIR into runnable code

---

## Part 1: What is AIR?

### The Final Intermediate Representation

AIR is the **last stop** before actual code. It's fully typed and ready for execution:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE COMPILATION PIPELINE                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Source Code                                                        │
│       ↓                                                              │
│   Tokens                                                             │
│       ↓                                                              │
│   AST (tree structure)                                               │
│       ↓                                                              │
│   ZIR (untyped instructions, per file)                              │
│       ↓                                                              │
│   AIR (typed instructions, per function)    ◄── YOU ARE HERE        │
│       ↓                                                              │
│   Machine Code / C Code / LLVM IR                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### ZIR vs AIR: What's the Difference?

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIR vs AIR COMPARISON                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Feature            ZIR                    AIR                       │
│ ─────────────      ─────────────────      ─────────────────         │
│ Typed?             NO                     YES                       │
│ Per what?          Per FILE               Per FUNCTION              │
│ Comptime code?     YES (still there)      NO (already evaluated)   │
│ Generic code?      YES (templates)        NO (instantiated)         │
│ Safety checks?     Abstract               Concrete instructions    │
│ Ready to execute?  NO                     YES                       │
│                                                                      │
│                                                                      │
│ ZIR says:  "add these two things"                                   │
│ AIR says:  "add these two 32-bit unsigned integers,                │
│             result is a 32-bit unsigned integer"                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Per-Function?

ZIR is per-file, but AIR is per-function. Why?

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHY AIR IS PER-FUNCTION                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. INCREMENTAL COMPILATION                                          │
│    ─────────────────────────                                        │
│    If you change one function, only regenerate AIR for that function
│    Other functions stay cached                                      │
│                                                                      │
│ 2. PARALLEL COMPILATION                                             │
│    ─────────────────────────                                        │
│    Different functions can be compiled on different CPU cores       │
│    func1 → Core 1                                                   │
│    func2 → Core 2                                                   │
│    func3 → Core 3                                                   │
│                                                                      │
│ 3. MEMORY EFFICIENCY                                                │
│    ─────────────────────────                                        │
│    Generate AIR for one function                                    │
│    Compile it to machine code                                       │
│    Free the AIR                                                     │
│    Move to next function                                            │
│    (Don't need all AIR in memory at once)                          │
│                                                                      │
│ 4. FUNCTION-LEVEL OPTIMIZATION                                      │
│    ─────────────────────────                                        │
│    Each function is self-contained                                  │
│    Optimizer can focus on one function at a time                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: Inside AIR Instructions

### AIR is More Specific Than ZIR

AIR has specialized instructions for exact operations:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIR vs AIR INSTRUCTIONS                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ZIR (vague):                                                        │
│                                                                      │
│   %3 = add(%1, %2)      // Add... something?                       │
│                                                                      │
│ AIR (specific):                                                      │
│                                                                      │
│   add           // Regular addition                                 │
│   add_safe      // Addition WITH overflow check                    │
│   add_wrap      // Addition that WRAPS on overflow (a +% b)        │
│   add_sat       // Addition that SATURATES (a +| b)                │
│   add_optimized // Addition where NaN is allowed (for floats)      │
│                                                                      │
│ Each variant tells the code generator EXACTLY what to do.          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Full Instruction Set

AIR has instructions for everything a program might need:

```
┌─────────────────────────────────────────────────────────────────────┐
│ AIR INSTRUCTION CATEGORIES                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. ARITHMETIC                                                       │
│    ─────────────────────────────                                    │
│    add, add_safe, add_wrap, add_sat                                │
│    sub, sub_safe, sub_wrap, sub_sat                                │
│    mul, mul_safe, mul_wrap, mul_sat                                │
│    div_trunc, div_floor, div_exact                                 │
│    mod, rem                                                         │
│    neg (negate)                                                     │
│                                                                      │
│ 2. COMPARISONS                                                      │
│    ─────────────────────────────                                    │
│    cmp_lt   (<)                                                    │
│    cmp_lte  (<=)                                                   │
│    cmp_eq   (==)                                                   │
│    cmp_neq  (!=)                                                   │
│    cmp_gte  (>=)                                                   │
│    cmp_gt   (>)                                                    │
│                                                                      │
│ 3. MEMORY OPERATIONS                                                │
│    ─────────────────────────────                                    │
│    alloc         // Reserve stack space                            │
│    load          // Read from memory                               │
│    store         // Write to memory                                │
│    memset        // Fill memory with value                         │
│    memcpy        // Copy memory                                    │
│                                                                      │
│ 4. CONTROL FLOW                                                     │
│    ─────────────────────────────                                    │
│    block         // Start a labeled block                          │
│    loop          // Infinite loop structure                        │
│    br            // Break/jump to label                            │
│    cond_br       // Conditional branch (if-else)                   │
│    switch_br     // Switch statement dispatch                      │
│    ret           // Return from function                           │
│                                                                      │
│ 5. FUNCTION CALLS                                                   │
│    ─────────────────────────────                                    │
│    call              // Regular function call                      │
│    call_always_tail  // Must be tail call optimized               │
│    call_never_tail   // Must NOT be tail call optimized           │
│    call_never_inline // Must NOT be inlined                        │
│                                                                      │
│ 6. BIT OPERATIONS                                                   │
│    ─────────────────────────────                                    │
│    bit_and, bit_or, bit_xor                                        │
│    shl (shift left), shr (shift right)                             │
│    clz (count leading zeros)                                       │
│    ctz (count trailing zeros)                                      │
│    popcount (count set bits)                                       │
│    byte_swap, bit_reverse                                          │
│                                                                      │
│ 7. FLOATING POINT                                                   │
│    ─────────────────────────────                                    │
│    sqrt, sin, cos, tan                                             │
│    exp, exp2, log, log2, log10                                     │
│    abs, floor, ceil, round, trunc_float                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### AIR Instruction Anatomy

Each AIR instruction has a tag and data:

```
┌─────────────────────────────────────────────────────────────────────┐
│ AIR INSTRUCTION STRUCTURE                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ struct Inst {                                                        │
│     tag: Tag,     // What operation (add, load, call, etc.)        │
│     data: Data,   // Operation-specific data                        │
│ }                                                                    │
│                                                                      │
│ The Data union can be:                                              │
│                                                                      │
│   no_op           // No extra data needed                          │
│                   // Example: ret with no value                    │
│                                                                      │
│   un_op           // One operand                                   │
│                   // Example: neg(%5)                              │
│                                                                      │
│   bin_op          // Two operands                                  │
│                   // Example: add(%3, %4)                          │
│                                                                      │
│   ty_op           // Type + operand                                │
│                   // Example: intcast(u64, %3)                     │
│                                                                      │
│   br              // Branch target + optional value                │
│                   // Example: br(loop_start, %5)                   │
│                                                                      │
│   ... and more                                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 3: What is Code Generation?

### The Final Translation

Code generation translates AIR into something that can actually run:

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT CODE GENERATION DOES                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ INPUT: AIR (abstract instructions)                                  │
│                                                                      │
│   %0 = arg(0)           // First parameter                         │
│   %1 = arg(1)           // Second parameter                        │
│   %2 = add(%0, %1)      // Add them                                │
│   ret(%2)               // Return result                           │
│                                                                      │
│ OUTPUT: Real executable code (one of these):                       │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ MACHINE CODE (bytes the CPU executes directly)              │  │
│   │                                                              │  │
│   │   89 f8        // mov eax, edi    (eax = param 0)          │  │
│   │   01 f0        // add eax, esi    (eax += param 1)         │  │
│   │   c3           // ret             (return eax)             │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ C CODE (to be compiled by a C compiler)                     │  │
│   │                                                              │  │
│   │   uint32_t add(uint32_t a, uint32_t b) {                   │  │
│   │       return a + b;                                         │  │
│   │   }                                                          │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ LLVM IR (to be optimized by LLVM)                           │  │
│   │                                                              │  │
│   │   define i32 @add(i32 %a, i32 %b) {                        │  │
│   │       %result = add i32 %a, %b                              │  │
│   │       ret i32 %result                                       │  │
│   │   }                                                          │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Core Challenge

Code generation must handle many details:

```
┌─────────────────────────────────────────────────────────────────────┐
│ CODE GENERATION CHALLENGES                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. REGISTER ALLOCATION                                              │
│    ─────────────────────────                                        │
│    AIR has unlimited "virtual registers" (%0, %1, %2, ...)         │
│    CPUs have limited physical registers (rax, rbx, rcx, ...)       │
│    Must decide which values go in which registers                  │
│    If not enough registers, must "spill" to stack memory           │
│                                                                      │
│ 2. INSTRUCTION SELECTION                                            │
│    ─────────────────────────                                        │
│    One AIR operation might need multiple machine instructions      │
│    Or one machine instruction might do multiple AIR operations     │
│                                                                      │
│    AIR: add_safe(%0, %1)                                           │
│    x86: add eax, ebx                                               │
│         jo overflow_handler   // Check overflow flag               │
│                                                                      │
│ 3. CALLING CONVENTIONS                                              │
│    ─────────────────────────                                        │
│    How do we pass arguments to functions?                          │
│    Different platforms have different rules!                       │
│                                                                      │
│    Linux x86-64:  First args in rdi, rsi, rdx, rcx, r8, r9        │
│    Windows x86-64: First args in rcx, rdx, r8, r9                  │
│    ARM64:         First args in x0-x7                              │
│                                                                      │
│ 4. MEMORY LAYOUT                                                    │
│    ─────────────────────────                                        │
│    How big is each type? How is it aligned?                        │
│    Different on 32-bit vs 64-bit systems                           │
│                                                                      │
│ 5. TARGET-SPECIFIC FEATURES                                        │
│    ─────────────────────────                                        │
│    Does the CPU have SSE? AVX? NEON?                               │
│    Can we use special instructions for better performance?         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 4: Why Multiple Backends?

### Zig Has Three Code Generation Strategies

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE THREE BACKENDS                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│                           AIR                                        │
│                            │                                         │
│              ┌─────────────┼─────────────┐                          │
│              ▼             ▼             ▼                          │
│       ┌──────────┐  ┌──────────┐  ┌──────────┐                     │
│       │    C     │  │   LLVM   │  │  NATIVE  │                     │
│       │ BACKEND  │  │ BACKEND  │  │ BACKENDS │                     │
│       └────┬─────┘  └────┬─────┘  └────┬─────┘                     │
│            │             │             │                            │
│            ▼             ▼             ▼                            │
│       ┌──────────┐  ┌──────────┐  ┌──────────┐                     │
│       │ C Source │  │ LLVM IR  │  │ Machine  │                     │
│       │   Code   │  │          │  │   Code   │                     │
│       └────┬─────┘  └────┬─────┘  └──────────┘                     │
│            │             │                                          │
│            ▼             ▼                                          │
│       ┌──────────┐  ┌──────────┐                                   │
│       │    C     │  │  LLVM    │                                   │
│       │ Compiler │  │ Optimize │                                   │
│       └────┬─────┘  └────┬─────┘                                   │
│            │             │                                          │
│            ▼             ▼                                          │
│       └──────────────────┴──────────────────┘                      │
│                         │                                           │
│                         ▼                                           │
│                  ┌──────────────┐                                   │
│                  │ Object File  │                                   │
│                  │   (.o)       │                                   │
│                  └──────────────┘                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Each Backend Has Its Purpose

```
┌─────────────────────────────────────────────────────────────────────┐
│ BACKEND COMPARISON                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ C BACKEND                                                        ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │                                                                  ││
│ │ What it does:  Generates C source code                          ││
│ │                                                                  ││
│ │ Why it exists:                                                   ││
│ │   • BOOTSTRAP: Can build Zig using ONLY a C compiler           ││
│ │   • PORTABILITY: Works on ANY platform with a C compiler        ││
│ │   • DEBUGGING: C code is human-readable                         ││
│ │                                                                  ││
│ │ Trade-offs:                                                      ││
│ │   ✓ Maximum portability                                         ││
│ │   ✓ No dependencies (just needs C compiler)                     ││
│ │   ✗ Slower compilation (two-step: Zig→C→binary)                ││
│ │   ✗ Less optimization than LLVM                                 ││
│ │                                                                  ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ LLVM BACKEND                                                     ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │                                                                  ││
│ │ What it does:  Generates LLVM IR, uses LLVM for optimization   ││
│ │                                                                  ││
│ │ Why it exists:                                                   ││
│ │   • OPTIMIZATION: LLVM has world-class optimizations           ││
│ │   • TARGETS: LLVM supports many CPU architectures              ││
│ │   • PRODUCTION: Best for release builds                         ││
│ │                                                                  ││
│ │ Trade-offs:                                                      ││
│ │   ✓ Best runtime performance                                    ││
│ │   ✓ Supports many targets (x86, ARM, RISC-V, WASM, ...)        ││
│ │   ✗ Slow compilation (LLVM is complex)                          ││
│ │   ✗ Large dependency (LLVM is huge)                             ││
│ │                                                                  ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ NATIVE BACKENDS (x86_64, aarch64, etc.)                         ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │                                                                  ││
│ │ What it does:  Generates machine code directly                  ││
│ │                                                                  ││
│ │ Why it exists:                                                   ││
│ │   • SPEED: Fastest compilation possible                         ││
│ │   • INCREMENTAL: Perfect for development cycle                  ││
│ │   • SELF-CONTAINED: No external dependencies                    ││
│ │                                                                  ││
│ │ Trade-offs:                                                      ││
│ │   ✓ Fastest compilation                                         ││
│ │   ✓ Great for development                                       ││
│ │   ✗ Less optimization than LLVM                                 ││
│ │   ✗ Must implement each target separately                       ││
│ │                                                                  ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### When to Use Each Backend

```
┌─────────────────────────────────────────────────────────────────────┐
│ CHOOSING A BACKEND                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ "I'm developing and want fast iteration"                            │
│   → NATIVE BACKEND                                                  │
│   Fastest compile times, good enough optimization                  │
│                                                                      │
│ "I'm building a release version"                                    │
│   → LLVM BACKEND                                                    │
│   Best runtime performance, full optimizations                     │
│                                                                      │
│ "I'm building Zig itself from source"                              │
│   → C BACKEND                                                       │
│   Only needs a C compiler, maximum portability                     │
│                                                                      │
│ "I'm targeting an exotic platform"                                  │
│   → C BACKEND (if it has a C compiler)                             │
│   → LLVM BACKEND (if LLVM supports it)                             │
│                                                                      │
│ "I'm debugging code generation"                                     │
│   → C BACKEND                                                       │
│   Output is human-readable C code                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: The C Backend in Detail

### Why C is Special

The C backend is crucial for Zig's **bootstrap**:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE BOOTSTRAP PROBLEM                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Problem: Zig is written in Zig. How do you compile Zig             │
│          if you don't already have a Zig compiler?                 │
│                                                                      │
│ The Chicken-and-Egg:                                                │
│                                                                      │
│   ┌──────────┐                                                      │
│   │ Zig Code │ ─── needs ───► Zig Compiler                         │
│   └──────────┘                     │                                │
│        ▲                           │                                │
│        │                           │                                │
│        └─────── is ───────────────┘                                │
│                                                                      │
│ Solution: The C Backend!                                            │
│                                                                      │
│   Step 1: Use existing Zig compiler to generate C code             │
│           Zig source → C source                                    │
│                                                                      │
│   Step 2: Commit the C source to the repository                    │
│           (This is checked in as "bootstrap C")                    │
│                                                                      │
│   Step 3: Anyone can build Zig using only a C compiler!            │
│           C source → C compiler → Zig binary                       │
│                                                                      │
│   Step 4: This new Zig can now compile Zig code normally           │
│                                                                      │
│ No need for a pre-existing Zig compiler on new systems!            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How the C Backend Works

```
┌─────────────────────────────────────────────────────────────────────┐
│ C BACKEND PROCESS                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ For each AIR instruction, emit equivalent C code:                  │
│                                                                      │
│ AIR Instruction          C Code Generated                          │
│ ───────────────────      ─────────────────────────────────         │
│ %0 = arg(0)              // param already named                    │
│ %1 = arg(1)              // param already named                    │
│ %2 = add(%0, %1)         uint32_t t0 = a + b;                      │
│ %3 = mul(%2, %0)         uint32_t t1 = t0 * a;                     │
│ ret(%3)                  return t1;                                │
│                                                                      │
│ The C backend maintains:                                            │
│                                                                      │
│   • A mapping from AIR refs to C variable names                    │
│   • Forward declarations for functions                             │
│   • Type definitions for Zig types                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Example: Zig to C Translation

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIG TO C EXAMPLE                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Zig source:                                                         │
│ ───────────                                                         │
│                                                                      │
│   pub fn max(a: i32, b: i32) i32 {                                 │
│       if (a > b) {                                                 │
│           return a;                                                 │
│       } else {                                                      │
│           return b;                                                 │
│       }                                                             │
│   }                                                                  │
│                                                                      │
│ AIR (simplified):                                                   │
│ ─────────────────                                                   │
│                                                                      │
│   %0 = arg(0)               // a: i32                              │
│   %1 = arg(1)               // b: i32                              │
│   %2 = cmp_gt(%0, %1)       // a > b                               │
│   cond_br(%2, then, else)   // if a > b                            │
│   then:                                                             │
│       ret(%0)               // return a                            │
│   else:                                                             │
│       ret(%1)               // return b                            │
│                                                                      │
│ C output:                                                           │
│ ─────────                                                           │
│                                                                      │
│   int32_t zig_max(int32_t a, int32_t b) {                          │
│       if (a > b) {                                                 │
│           return a;                                                 │
│       } else {                                                      │
│           return b;                                                 │
│       }                                                             │
│   }                                                                  │
│                                                                      │
│ Notice: The C code looks almost identical to the Zig source!       │
│ That's intentional - makes debugging easier.                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Handling Name Conflicts

C has reserved keywords. The backend must escape them:

```
┌─────────────────────────────────────────────────────────────────────┐
│ C NAME ESCAPING                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Problem: Zig allows names that are C keywords                      │
│                                                                      │
│   // This is valid Zig!                                            │
│   const auto = 5;       // "auto" is a C keyword                   │
│   const register = 10;  // "register" is a C keyword               │
│   const int = 15;       // "int" is a C keyword                    │
│                                                                      │
│ Solution: Prefix with "zig_e_" (e for escape)                      │
│                                                                      │
│   Zig name          C name                                         │
│   ─────────         ──────────────                                 │
│   auto              zig_e_auto                                     │
│   register          zig_e_register                                 │
│   int               zig_e_int                                      │
│   normal_name       normal_name    (no escape needed)              │
│                                                                      │
│ Reserved words that need escaping:                                 │
│                                                                      │
│   C keywords:    auto, break, case, char, const, continue,         │
│                  default, do, double, else, enum, extern,          │
│                  float, for, goto, if, int, long, register,        │
│                  return, short, signed, sizeof, static,            │
│                  struct, switch, typedef, union, unsigned,         │
│                  void, volatile, while                              │
│                                                                      │
│   C standard:    bool, true, false, va_start, va_end, va_arg       │
│                                                                      │
│   Platform:      max, min (Windows defines these as macros!)       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 6: The LLVM Backend

### What is LLVM?

```
┌─────────────────────────────────────────────────────────────────────┐
│ LLVM EXPLAINED                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ LLVM is a compiler toolkit used by many languages:                 │
│   • Clang (C/C++)                                                  │
│   • Rust                                                            │
│   • Swift                                                           │
│   • Julia                                                           │
│   • And Zig!                                                        │
│                                                                      │
│ LLVM provides:                                                      │
│                                                                      │
│   1. LLVM IR (Intermediate Representation)                         │
│      A portable assembly-like language                             │
│                                                                      │
│   2. Optimization passes                                            │
│      World-class optimizations developed over 20+ years            │
│                                                                      │
│   3. Code generators                                                │
│      Targets: x86, ARM, RISC-V, WebAssembly, and more             │
│                                                                      │
│ The deal:                                                           │
│   You generate LLVM IR                                             │
│   LLVM handles optimization and machine code                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### LLVM IR Explained

```
┌─────────────────────────────────────────────────────────────────────┐
│ LLVM IR EXAMPLE                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Zig source:                                                         │
│                                                                      │
│   pub fn add(a: u32, b: u32) u32 {                                 │
│       return a + b;                                                 │
│   }                                                                  │
│                                                                      │
│ LLVM IR generated:                                                  │
│                                                                      │
│   define i32 @add(i32 %a, i32 %b) {                                │
│   entry:                                                            │
│       %result = add i32 %a, %b                                     │
│       ret i32 %result                                              │
│   }                                                                  │
│                                                                      │
│ LLVM IR anatomy:                                                    │
│                                                                      │
│   define i32 @add(...)                                             │
│   ↑      ↑    ↑                                                    │
│   │      │    └── function name                                    │
│   │      └── return type (32-bit integer)                          │
│   └── "define" means this is a function definition                 │
│                                                                      │
│   %a, %b, %result                                                  │
│   ↑                                                                 │
│   └── % prefix means "virtual register" or "value"                 │
│                                                                      │
│   add i32 %a, %b                                                   │
│   ↑   ↑   ↑    ↑                                                   │
│   │   │   └────┴── operands                                        │
│   │   └── type                                                      │
│   └── instruction                                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### What LLVM Optimizes

```
┌─────────────────────────────────────────────────────────────────────┐
│ LLVM OPTIMIZATIONS                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ LLVM applies many optimization passes:                             │
│                                                                      │
│ 1. DEAD CODE ELIMINATION                                           │
│    ─────────────────────────                                        │
│    Remove code that's never executed                               │
│    Remove computations whose results are never used                │
│                                                                      │
│ 2. INLINING                                                         │
│    ─────────────────────────                                        │
│    Replace function calls with function body                       │
│    Eliminates call overhead for small functions                    │
│                                                                      │
│ 3. CONSTANT FOLDING                                                 │
│    ─────────────────────────                                        │
│    x = 3 + 4  →  x = 7  (computed at compile time)                │
│                                                                      │
│ 4. LOOP OPTIMIZATIONS                                               │
│    ─────────────────────────                                        │
│    Loop unrolling: repeat loop body to reduce branch overhead     │
│    Loop invariant code motion: move constant computations out     │
│    Vectorization: use SIMD instructions                            │
│                                                                      │
│ 5. REGISTER ALLOCATION                                              │
│    ─────────────────────────                                        │
│    Decide which values go in CPU registers                        │
│    Minimize memory access (registers are faster)                   │
│                                                                      │
│ 6. INSTRUCTION SCHEDULING                                           │
│    ─────────────────────────                                        │
│    Reorder instructions to hide latency                           │
│    Keep CPU pipeline full                                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 7: Native Backends

### Direct Machine Code Generation

Native backends skip the middleman:

```
┌─────────────────────────────────────────────────────────────────────┐
│ NATIVE BACKEND APPROACH                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ LLVM approach:                                                      │
│   AIR → LLVM IR → LLVM optimizer → LLVM codegen → Machine code    │
│   (Multiple steps, slow but very optimized)                        │
│                                                                      │
│ Native approach:                                                    │
│   AIR → Machine code                                               │
│   (One step, fast but less optimized)                              │
│                                                                      │
│ The native backends directly emit:                                 │
│   • x86_64 instructions                                            │
│   • ARM64 instructions                                              │
│   • etc.                                                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### x86_64 Backend Example

```
┌─────────────────────────────────────────────────────────────────────┐
│ x86_64 CODE GENERATION                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Zig source:                                                         │
│                                                                      │
│   pub fn square(x: i32) i32 {                                      │
│       return x * x;                                                 │
│   }                                                                  │
│                                                                      │
│ AIR:                                                                │
│                                                                      │
│   %0 = arg(0)           // x in edi register                       │
│   %1 = mul(%0, %0)      // x * x                                   │
│   ret(%1)               // return result                           │
│                                                                      │
│ x86_64 machine code:                                               │
│                                                                      │
│   Bytes        Assembly          Meaning                           │
│   ──────       ──────────────    ──────────────────────────        │
│   89 f8        mov eax, edi      Copy x to result register         │
│   0f af c7     imul eax, edi     Multiply eax by x                │
│   c3           ret               Return (result in eax)            │
│                                                                      │
│ That's just 6 bytes of machine code!                               │
│                                                                      │
│ The native backend knows x86_64 calling convention:                │
│   • First integer argument → edi register                          │
│   • Return value → eax register                                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Register Allocation

The hardest part of native code generation:

```
┌─────────────────────────────────────────────────────────────────────┐
│ REGISTER ALLOCATION                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Problem:                                                            │
│                                                                      │
│   AIR can have hundreds of values: %0, %1, %2, ... %500            │
│   x86_64 only has 16 registers: rax, rbx, rcx, ... r15            │
│                                                                      │
│ Simple AIR:                     Reality:                           │
│                                                                      │
│   %0 = ...                      16 registers                       │
│   %1 = ...                      But many values                    │
│   %2 = ...                      need to be live                    │
│   %3 = ...                      at the same time!                  │
│   %4 = ...                                                         │
│   ... (many more)                                                  │
│                                                                      │
│ Solution: Spilling                                                  │
│                                                                      │
│   When we run out of registers:                                    │
│   1. Pick a value currently in a register                          │
│   2. Save it to stack memory ("spill")                             │
│   3. Use that register for the new value                           │
│   4. Later, reload from stack if needed                            │
│                                                                      │
│   Good allocators minimize spills (memory access is slow!)         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 8: Liveness Analysis

### What is Liveness?

Before code generation, we analyze which values are "alive":

```
┌─────────────────────────────────────────────────────────────────────┐
│ LIVENESS ANALYSIS                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ A value is "live" if it will be used later.                        │
│ A value is "dead" if it will never be used again.                  │
│                                                                      │
│ Example:                                                            │
│                                                                      │
│   %0 = arg(0)              ─┐                                      │
│   %1 = arg(1)              ─┼─ %0, %1 are live                     │
│   %2 = add(%0, %1)         ─┼─ %0, %1, %2 are live                 │
│   %3 = mul(%2, %0)         ─┼─ %1 is DEAD (never used after %2)   │
│   ret(%3)                   │  %0, %2, %3 are live                 │
│                             │  After ret: all dead                 │
│                                                                      │
│ Visual:                                                             │
│                                                                      │
│   Instruction    %0    %1    %2    %3                              │
│   ───────────    ───   ───   ───   ───                              │
│   %0 = arg(0)    BORN                                               │
│   %1 = arg(1)    live  BORN                                         │
│   %2 = add       live  DIES  BORN                                   │
│   %3 = mul       DIES        live  BORN                             │
│   ret            -     -     DIES  DIES                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Liveness Matters

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHY LIVENESS MATTERS                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. REGISTER ALLOCATION                                              │
│    ─────────────────────────                                        │
│    If %1 dies before %3 is born, they can share a register!       │
│                                                                      │
│    %0 → rax                                                        │
│    %1 → rbx  (dies at %2)                                         │
│    %2 → rbx  (reuses rbx!)                                        │
│    %3 → rcx                                                        │
│                                                                      │
│    Without liveness: would need 4 registers                        │
│    With liveness: only need 3 registers                            │
│                                                                      │
│ 2. DEAD CODE ELIMINATION                                            │
│    ─────────────────────────                                        │
│    If a value is computed but never used, don't generate code!    │
│                                                                      │
│    %0 = expensive_computation()  // Result never used             │
│    %1 = simple_thing()                                             │
│    ret(%1)                                                          │
│                                                                      │
│    Liveness shows %0 is dead → skip generating it!                │
│                                                                      │
│ 3. MEMORY EFFICIENCY                                                │
│    ─────────────────────────                                        │
│    Free memory as soon as values die                               │
│    Reuse stack slots for non-overlapping values                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 9: Complete Example - All Three Backends

Let's trace the same function through all three backends:

```
┌─────────────────────────────────────────────────────────────────────┐
│ SOURCE CODE                                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   pub fn factorial(n: u32) u32 {                                   │
│       if (n <= 1) {                                                │
│           return 1;                                                 │
│       }                                                             │
│       return n * factorial(n - 1);                                 │
│   }                                                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ AIR (from Sema)                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   %0 = arg(0)                       // n: u32                      │
│   %1 = int(1)                       // constant 1                  │
│   %2 = cmp_lte(%0, %1)              // n <= 1                      │
│   cond_br(%2, early_ret, continue)  // if n <= 1                   │
│                                                                      │
│ early_ret:                                                          │
│   ret(%1)                           // return 1                    │
│                                                                      │
│ continue:                                                           │
│   %3 = sub(%0, %1)                  // n - 1                       │
│   %4 = call(factorial, %3)          // factorial(n - 1)            │
│   %5 = mul(%0, %4)                  // n * factorial(n - 1)        │
│   ret(%5)                           // return result               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### C Backend Output

```
┌─────────────────────────────────────────────────────────────────────┐
│ C BACKEND OUTPUT                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   uint32_t factorial(uint32_t n) {                                 │
│       if (n <= 1) {                                                │
│           return 1;                                                 │
│       }                                                             │
│       uint32_t t0 = n - 1;                                         │
│       uint32_t t1 = factorial(t0);                                 │
│       uint32_t t2 = n * t1;                                        │
│       return t2;                                                    │
│   }                                                                  │
│                                                                      │
│ → This C code can be compiled by any C compiler                    │
│ → Human readable for debugging                                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### LLVM Backend Output

```
┌─────────────────────────────────────────────────────────────────────┐
│ LLVM IR OUTPUT                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   define i32 @factorial(i32 %n) {                                  │
│   entry:                                                            │
│       %cmp = icmp ule i32 %n, 1                                    │
│       br i1 %cmp, label %early_ret, label %continue                │
│                                                                      │
│   early_ret:                                                        │
│       ret i32 1                                                     │
│                                                                      │
│   continue:                                                         │
│       %n_minus_1 = sub i32 %n, 1                                   │
│       %rec_result = call i32 @factorial(i32 %n_minus_1)            │
│       %result = mul i32 %n, %rec_result                            │
│       ret i32 %result                                              │
│   }                                                                  │
│                                                                      │
│ → LLVM will optimize this (maybe convert to loop)                  │
│ → LLVM generates machine code for target CPU                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Native x86_64 Output

```
┌─────────────────────────────────────────────────────────────────────┐
│ x86_64 ASSEMBLY OUTPUT                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   factorial:                                                        │
│       cmp edi, 1           ; compare n with 1                      │
│       jbe .early_ret       ; if n <= 1, jump                       │
│                                                                      │
│       push rbx             ; save rbx (callee-saved)               │
│       mov ebx, edi         ; save n in rbx                         │
│       dec edi              ; n - 1                                 │
│       call factorial       ; recursive call                        │
│       imul eax, ebx        ; n * factorial(n-1)                    │
│       pop rbx              ; restore rbx                           │
│       ret                                                           │
│                                                                      │
│   .early_ret:                                                       │
│       mov eax, 1           ; return 1                              │
│       ret                                                           │
│                                                                      │
│ → Direct machine code, no intermediate steps                       │
│ → Fastest compilation, reasonable performance                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 10: The Big Picture

### Complete Code Generation Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE COMPLETE PIPELINE                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                     Zig Source Code                          │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │          Tokenizer → Parser → AST → AstGen → ZIR            │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                  Sema: Type Checking                         │  │
│   │        ZIR → AIR (one per function, fully typed)            │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                  Liveness Analysis                           │  │
│   │         Determine which values are used where               │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│            ┌───────────────┼───────────────┐                       │
│            ▼               ▼               ▼                       │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│   │  C Backend  │  │LLVM Backend │  │Native Backs │               │
│   │             │  │             │  │             │               │
│   │ AIR → C src │  │ AIR → LLVM  │  │ AIR → asm   │               │
│   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘               │
│          │                │                │                       │
│          ▼                ▼                │                       │
│   ┌─────────────┐  ┌─────────────┐        │                       │
│   │  C Compiler │  │LLVM Passes  │        │                       │
│   │ (gcc/clang) │  │& Codegen    │        │                       │
│   └──────┬──────┘  └──────┬──────┘        │                       │
│          │                │                │                       │
│          └────────────────┴────────────────┘                       │
│                           │                                        │
│                           ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                    Object Files (.o)                         │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                      Linker                                  │  │
│   │              Combine into executable                        │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                  Executable Binary                           │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Summary: What We Learned

```
┌─────────────────────────────────────────────────────────────────────┐
│ KEY POINTS                                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. AIR IS THE FINAL IR                                              │
│    • Fully typed                                                    │
│    • Per-function (enables parallel compilation)                   │
│    • All comptime evaluated                                         │
│    • Ready for code generation                                      │
│                                                                      │
│ 2. THREE BACKENDS SERVE DIFFERENT NEEDS                             │
│    • C Backend: Bootstrap, portability                             │
│    • LLVM Backend: Maximum optimization                            │
│    • Native Backends: Fastest compilation                          │
│                                                                      │
│ 3. CODE GENERATION IS HARD                                          │
│    • Register allocation                                            │
│    • Instruction selection                                          │
│    • Calling conventions                                            │
│    • Platform differences                                           │
│                                                                      │
│ 4. LIVENESS ANALYSIS ENABLES OPTIMIZATIONS                         │
│    • Dead code elimination                                          │
│    • Register reuse                                                 │
│    • Memory efficiency                                              │
│                                                                      │
│ 5. THE MULTI-BACKEND ARCHITECTURE IS FLEXIBLE                       │
│    • Same frontend for all backends                                │
│    • Choose backend based on needs                                 │
│    • Can add new backends without changing the rest                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Conclusion

Code generation is where the abstract meets the concrete. After all the parsing, type checking, and optimization, this is where Zig code becomes something that can actually run.

The multi-backend architecture is one of Zig's strengths:
- **C Backend** makes Zig self-bootstrapping and maximally portable
- **LLVM Backend** provides production-quality optimizations
- **Native Backends** enable the fast development cycle Zig is known for

In the final article, we'll explore the **linker** - how all these compiled pieces get combined into a single executable program.

---

**Previous**: [Part 5: Semantic Analysis](./05-sema.md)
**Next**: [Part 7: Linking](./07-linking.md)

**Series Index**:
1. [Bootstrap Process](./01-bootstrap-process.md)
2. [Tokenizer](./02-tokenizer.md)
3. [Parser and AST](./03-parser-ast.md)
4. [ZIR Generation](./04-zir-generation.md)
5. [Semantic Analysis](./05-sema.md)
6. **AIR and Code Generation** (this article)
7. [Linking](./07-linking.md)
