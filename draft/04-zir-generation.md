---
title: "Zig Compiler Internals Part 4: ZIR Generation"
date: 2025-12-17
---

# Zig Compiler Internals Part 4: ZIR Generation

*From trees to instructions with AstGen*

---

## Introduction

After parsing produces the AST, the next step is to convert it into **ZIR** (Zig Intermediate Representation). But before we dive into how this works, let's understand **why** we need ZIR in the first place.

---

## Part 1: Why Do We Need ZIR?

### The Problem: Trees Are Hard to Execute

The AST (Abstract Syntax Tree) is great for representing code structure, but it's terrible for execution. Here's why:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE AST PROBLEM                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Code: result = a + b * c                                            │
│                                                                      │
│ AST looks like this:                                                │
│                                                                      │
│              assign                                                  │
│             /      \                                                 │
│         result      +                                                │
│                   /   \                                              │
│                  a     *                                             │
│                       / \                                            │
│                      b   c                                           │
│                                                                      │
│ Questions a CPU would ask:                                          │
│                                                                      │
│   ❓ "Where do I start?"                                            │
│   ❓ "What do I do first?"                                          │
│   ❓ "How do I traverse this tree?"                                 │
│   ❓ "Where do intermediate values go?"                             │
│                                                                      │
│ Trees require INTERPRETATION (walking/visiting) - slow!             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Solution: Linear Instructions

CPUs don't execute trees - they execute **sequences of instructions**, one after another:

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT CPUs UNDERSTAND                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Same code: result = a + b * c                                       │
│                                                                      │
│ As LINEAR INSTRUCTIONS:                                              │
│                                                                      │
│   Step 1:  temp1 = b * c      // First, multiply                    │
│   Step 2:  temp2 = a + temp1  // Then, add                          │
│   Step 3:  result = temp2     // Finally, assign                    │
│                                                                      │
│ CPU can execute this directly:                                      │
│   ✓ Start at step 1                                                 │
│   ✓ Go to step 2                                                    │
│   ✓ Go to step 3                                                    │
│   ✓ Done!                                                           │
│                                                                      │
│ This is MUCH faster than walking a tree!                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### ZIR = Zig's Linear Instruction Format

ZIR converts the tree into a linear sequence that's easier to work with:

```
┌─────────────────────────────────────────────────────────────────────┐
│ AST → ZIR TRANSFORMATION                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ BEFORE (AST - tree structure):                                      │
│                                                                      │
│              assign                                                  │
│             /      \                                                 │
│         result      +           Must walk tree recursively          │
│                   /   \         to figure out execution order       │
│                  a     *                                             │
│                       / \                                            │
│                      b   c                                           │
│                                                                      │
│                        │                                             │
│                        ▼                                             │
│                                                                      │
│ AFTER (ZIR - linear instructions):                                  │
│                                                                      │
│   %1 = load(b)           // Read b from memory                      │
│   %2 = load(c)           // Read c from memory                      │
│   %3 = mul(%1, %2)       // Multiply: b * c                         │
│   %4 = load(a)           // Read a from memory                      │
│   %5 = add(%4, %3)       // Add: a + (b * c)                        │
│   %6 = store(result, %5) // Store to result                         │
│                                                                      │
│   Each instruction clearly says:                                    │
│   - What operation to do                                            │
│   - What inputs to use (by reference number)                        │
│   - Result gets a reference number for later use                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: What is an "Intermediate Representation"?

### The Compiler as a Translator

Think of a compiler as a translator between languages:

```
┌─────────────────────────────────────────────────────────────────────┐
│ COMPILATION AS TRANSLATION                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Source Language          →          Target Language                 │
│ (Human-friendly)                    (Machine-friendly)              │
│                                                                      │
│ ┌─────────────────┐                 ┌─────────────────┐            │
│ │                 │                 │                 │            │
│ │  fn add(a, b)   │      ???        │  mov rax, rdi   │            │
│ │    return a+b   │  ─────────►     │  add rax, rsi   │            │
│ │  }              │                 │  ret            │            │
│ │                 │                 │                 │            │
│ └─────────────────┘                 └─────────────────┘            │
│                                                                      │
│ These are VERY different! Hard to translate directly.               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Not Translate Directly?

Direct translation is problematic:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PROBLEMS WITH DIRECT TRANSLATION                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. SOURCE IS HIGH-LEVEL                                             │
│    - Abstract concepts (functions, types, loops)                    │
│    - No concern for memory layout                                   │
│    - No concern for CPU registers                                   │
│                                                                      │
│ 2. TARGET IS LOW-LEVEL                                              │
│    - Concrete operations (add, mov, jump)                           │
│    - Specific memory addresses                                      │
│    - Specific CPU registers                                         │
│                                                                      │
│ 3. DIFFERENT TARGETS NEED DIFFERENT OUTPUT                          │
│    - x86-64 has different instructions than ARM                     │
│    - WebAssembly is completely different                            │
│    - We don't want to rewrite the whole compiler for each!         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Solution: Intermediate Steps

Instead of one big jump, we take small steps through "intermediate representations":

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE COMPILER PIPELINE                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Source Code (very high level)                                     │
│        │                                                            │
│        │  "Lower" = make more concrete                              │
│        ▼                                                            │
│   ┌─────────┐                                                       │
│   │   AST   │  Still high-level, but structured                    │
│   └────┬────┘                                                       │
│        │                                                            │
│        ▼                                                            │
│   ┌─────────┐                                                       │
│   │   ZIR   │  Linear instructions, but no types yet    ◄── HERE   │
│   └────┬────┘                                                       │
│        │                                                            │
│        ▼                                                            │
│   ┌─────────┐                                                       │
│   │   AIR   │  Typed instructions, machine-independent             │
│   └────┬────┘                                                       │
│        │                                                            │
│        ▼                                                            │
│   Machine Code (very low level)                                     │
│                                                                      │
│                                                                      │
│ Each step makes the code a LITTLE more concrete.                    │
│ No single step is too big of a jump.                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Analogy: Recipe Translation

Think of it like translating a recipe from French to English to a shopping list:

```
┌─────────────────────────────────────────────────────────────────────┐
│ RECIPE ANALOGY                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ French Recipe (Source):                                             │
│   "Préparez un gâteau au chocolat avec de la crème"                │
│                                                                      │
│        ↓ (Parse: understand structure)                              │
│                                                                      │
│ Structured Recipe (AST):                                            │
│   Make:                                                              │
│     - Type: Cake                                                    │
│     - Flavor: Chocolate                                             │
│     - Topping: Cream                                                │
│                                                                      │
│        ↓ (AstGen: make actionable)                                  │
│                                                                      │
│ Step-by-Step Instructions (ZIR):                                    │
│   1. Get chocolate                                                  │
│   2. Get flour                                                      │
│   3. Mix ingredients                                                │
│   4. Bake at ??? degrees  ← Temperature not specified yet!         │
│   5. Add cream topping                                              │
│                                                                      │
│        ↓ (Sema: fill in details)                                    │
│                                                                      │
│ Detailed Instructions (AIR):                                        │
│   1. Get 200g chocolate                                             │
│   2. Get 300g flour                                                 │
│   3. Mix for 5 minutes                                              │
│   4. Bake at 350°F for 30 minutes                                   │
│   5. Add 100ml cream topping                                        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 3: What Makes ZIR Special?

### ZIR is "Untyped" - What Does That Mean?

```
┌─────────────────────────────────────────────────────────────────────┐
│ TYPED vs UNTYPED                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ TYPED (knows exact types):                                          │
│                                                                      │
│   const x: u32 = 5;         // We know x is a 32-bit unsigned int  │
│   const y: u32 = 10;        // We know y is a 32-bit unsigned int  │
│   const z: u32 = x + y;     // Addition uses 32-bit math           │
│                                                                      │
│   The compiler knows:                                                │
│   - Exactly how many bytes each variable uses                       │
│   - Exactly which CPU instruction to use for addition               │
│   - Whether the operation is valid (can't add u32 to string)       │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ UNTYPED (doesn't know types yet):                                   │
│                                                                      │
│   %1 = load("x")            // Load something called "x"           │
│   %2 = load("y")            // Load something called "y"           │
│   %3 = add(%1, %2)          // Add them (somehow)                  │
│                                                                      │
│   The compiler DOESN'T know yet:                                    │
│   - Are these integers? Floats? Something else?                     │
│   - Is this addition valid?                                         │
│   - How many bytes are involved?                                    │
│                                                                      │
│   These questions are answered LATER during "Sema" (type checking) │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Keep ZIR Untyped?

This seems backwards - why not figure out types immediately? There are excellent reasons:

```
┌─────────────────────────────────────────────────────────────────────┐
│ REASON 1: CACHING                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ZIR can be saved to disk and reused!                                │
│                                                                      │
│ First compile:                                                       │
│   source.zig  ──►  [Parse]  ──►  [AstGen]  ──►  source.zir (saved) │
│                                                                      │
│ Second compile (source unchanged):                                  │
│   source.zir (loaded from disk)  ──►  [Sema]  ──►  ...             │
│                                                                      │
│ Skip parsing and AstGen entirely! Much faster rebuilds.             │
│                                                                      │
│ If ZIR contained type info, we couldn't cache it - changing a type │
│ in one file would invalidate ZIR in other files.                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ REASON 2: GENERICS (same code, different types)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Consider this generic function:                                      │
│                                                                      │
│   fn add(comptime T: type, a: T, b: T) T {                         │
│       return a + b;                                                 │
│   }                                                                  │
│                                                                      │
│ This SINGLE function can be called with:                            │
│   - add(u32, 5, 10)      → uses 32-bit integer addition            │
│   - add(f64, 1.5, 2.5)   → uses 64-bit float addition              │
│   - add(i8, 1, 2)        → uses 8-bit integer addition             │
│                                                                      │
│ With UNTYPED ZIR:                                                   │
│   - Generate ZIR ONCE for the function                              │
│   - Sema instantiates it multiple times with different types       │
│                                                                      │
│ With TYPED IR:                                                      │
│   - Would need to generate separate IR for each type combination   │
│   - Much more complex and wasteful                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ REASON 3: LAZY ANALYSIS                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Not all code needs to be analyzed!                                  │
│                                                                      │
│   fn usedFunction() void {                                          │
│       // This WILL be type-checked                                  │
│   }                                                                  │
│                                                                      │
│   fn unusedFunction() void {                                        │
│       // This WON'T be type-checked (never called)                 │
│       // Saves time!                                                │
│   }                                                                  │
│                                                                      │
│ With UNTYPED ZIR:                                                   │
│   - Generate ZIR for everything (fast, no type checking)           │
│   - Only type-check functions that are actually used               │
│                                                                      │
│ With TYPED IR:                                                      │
│   - Would need to type-check everything upfront                    │
│   - Wastes time on unused code                                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 4: How ZIR Instructions Work

### Instruction Format Explained

Every ZIR instruction has two parts:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIR INSTRUCTION ANATOMY                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │               ZIR Instruction                                    ││
│ │  ┌───────────────────┬─────────────────────────────────────┐   ││
│ │  │       TAG         │              DATA                    │   ││
│ │  │  (what to do)     │    (what to do it with)             │   ││
│ │  └───────────────────┴─────────────────────────────────────┘   ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
│ Examples:                                                            │
│                                                                      │
│   TAG: .add                                                         │
│   DATA: { lhs: %3, rhs: %5 }                                       │
│   Meaning: "Add the values from instruction 3 and instruction 5"   │
│                                                                      │
│   TAG: .load                                                        │
│   DATA: { operand: %2 }                                            │
│   Meaning: "Load the value that instruction 2 points to"           │
│                                                                      │
│   TAG: .int                                                         │
│   DATA: { value: 42 }                                              │
│   Meaning: "The integer literal 42"                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Reference Numbers Explained

Each instruction gets a "reference number" (like %1, %2, %3). This is how instructions refer to each other:

```
┌─────────────────────────────────────────────────────────────────────┐
│ HOW INSTRUCTIONS REFERENCE EACH OTHER                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Code: x = 5 + 3                                                     │
│                                                                      │
│ ZIR:                                                                │
│   %1 = int(5)       // Instruction 1 produces the value 5          │
│   %2 = int(3)       // Instruction 2 produces the value 3          │
│   %3 = add(%1, %2)  // Instruction 3 adds results of %1 and %2     │
│   %4 = store(x, %3) // Instruction 4 stores result of %3 to x      │
│                                                                      │
│ Visual:                                                              │
│                                                                      │
│   %1 ──────────┐                                                    │
│   (value: 5)   │                                                    │
│                ├──► %3 ──────────┐                                  │
│   %2 ──────────┘    (5 + 3 = 8)  │                                  │
│   (value: 3)                     ├──► %4                            │
│                                  │    (store 8 to x)                │
│                   x ─────────────┘                                  │
│                   (location)                                         │
│                                                                      │
│ Think of it like variables in a program:                            │
│   temp1 = 5                                                         │
│   temp2 = 3                                                         │
│   temp3 = temp1 + temp2                                             │
│   x = temp3                                                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Common Instruction Types

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIR INSTRUCTION CATEGORIES                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. LITERALS (create values)                                         │
│    ──────────────────────────                                       │
│    .int           → Integer literal       %1 = int(42)             │
│    .float         → Float literal         %1 = float(3.14)         │
│    .str           → String literal        %1 = str("hello")        │
│                                                                      │
│                                                                      │
│ 2. ARITHMETIC (math operations)                                     │
│    ──────────────────────────                                       │
│    .add           → Addition              %3 = add(%1, %2)         │
│    .sub           → Subtraction           %3 = sub(%1, %2)         │
│    .mul           → Multiplication        %3 = mul(%1, %2)         │
│    .div           → Division              %3 = div(%1, %2)         │
│                                                                      │
│                                                                      │
│ 3. COMPARISON (produce true/false)                                  │
│    ──────────────────────────                                       │
│    .cmp_eq        → Equal                 %3 = cmp_eq(%1, %2)      │
│    .cmp_neq       → Not equal             %3 = cmp_neq(%1, %2)     │
│    .cmp_lt        → Less than             %3 = cmp_lt(%1, %2)      │
│    .cmp_gt        → Greater than          %3 = cmp_gt(%1, %2)      │
│                                                                      │
│                                                                      │
│ 4. MEMORY (read/write memory)                                       │
│    ──────────────────────────                                       │
│    .load          → Read from pointer     %2 = load(%1)            │
│    .store         → Write to pointer      store(%1, %2)            │
│    .alloc         → Reserve stack space   %1 = alloc(u32)          │
│                                                                      │
│                                                                      │
│ 5. CONTROL FLOW (change execution order)                            │
│    ──────────────────────────                                       │
│    .block         → Start a block         block: { ... }           │
│    .condbr        → Conditional branch    condbr(%1, then, else)   │
│    .br            → Unconditional branch  br(target)               │
│    .ret           → Return from function  ret(%1)                  │
│                                                                      │
│                                                                      │
│ 6. FUNCTION (function-related)                                      │
│    ──────────────────────────                                       │
│    .param         → Function parameter    %1 = param(0)            │
│    .call          → Call a function       %2 = call(%1, args...)   │
│    .func          → Define a function     func(body, ...)          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Step-by-Step Examples

### Example 1: Simple Addition

Let's trace how `const z = x + y;` becomes ZIR:

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXAMPLE: const z = x + y;                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ STEP 1: Start with the AST                                          │
│ ─────────────────────────────                                       │
│                                                                      │
│   AST structure:                                                    │
│                                                                      │
│           const_decl                                                │
│           /    |    \                                               │
│         "z"  type    +                                              │
│              (none) / \                                              │
│                    x   y                                            │
│                                                                      │
│ STEP 2: Process the right side first (x + y)                        │
│ ─────────────────────────────                                       │
│                                                                      │
│   We need to generate ZIR for the "+" node.                         │
│   But "+" needs its operands first!                                 │
│                                                                      │
│   So we process left-to-right, bottom-up:                          │
│                                                                      │
│   a) Process "x" (identifier)                                       │
│      → Need to find where "x" is defined                           │
│      → Generate: %1 = load("x")                                    │
│                                                                      │
│   b) Process "y" (identifier)                                       │
│      → Need to find where "y" is defined                           │
│      → Generate: %2 = load("y")                                    │
│                                                                      │
│   c) Process "+" (binary operator)                                  │
│      → Generate: %3 = add(%1, %2)                                  │
│                                                                      │
│ STEP 3: Process the const declaration                               │
│ ─────────────────────────────                                       │
│                                                                      │
│   d) Allocate space for "z"                                         │
│      → Generate: %4 = alloc()                                      │
│                                                                      │
│   e) Store the result                                               │
│      → Generate: %5 = store(%4, %3)                                │
│                                                                      │
│ FINAL ZIR:                                                          │
│ ─────────────────────────────                                       │
│                                                                      │
│   %1 = load("x")        // Get value of x                          │
│   %2 = load("y")        // Get value of y                          │
│   %3 = add(%1, %2)      // Add them                                │
│   %4 = alloc()          // Make space for z                        │
│   %5 = store(%4, %3)    // Store result in z                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Example 2: If Expression

Let's trace `const max = if (a > b) a else b;`:

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXAMPLE: const max = if (a > b) a else b;                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ AST structure:                                                      │
│                                                                      │
│              const_decl                                             │
│             /    |    \                                             │
│          "max" type   if_expr                                       │
│                (none) /  |   \                                       │
│                     >  "a"  "b"                                     │
│                    / \   ↑    ↑                                     │
│                   a   b  │    │                                     │
│                         then else                                   │
│                                                                      │
│ ZIR GENERATION:                                                     │
│ ─────────────────────────────                                       │
│                                                                      │
│ 1. Generate condition (a > b):                                      │
│    %1 = load("a")                                                   │
│    %2 = load("b")                                                   │
│    %3 = cmp_gt(%1, %2)      // Is a > b?                           │
│                                                                      │
│ 2. Generate conditional branch:                                     │
│    %4 = condbr(%3)          // Branch based on comparison          │
│          │                                                          │
│          ├──► then_block:                                          │
│          │      %5 = load("a")    // If true, result is a          │
│          │      br(end, %5)       // Jump to end with value        │
│          │                                                          │
│          └──► else_block:                                          │
│                 %6 = load("b")    // If false, result is b         │
│                 br(end, %6)       // Jump to end with value        │
│                                                                      │
│ 3. End block collects the result:                                  │
│    end:                                                              │
│      %7 = block_result        // Either %5 or %6                   │
│                                                                      │
│ 4. Store in "max":                                                  │
│    %8 = store("max", %7)                                           │
│                                                                      │
│ VISUAL FLOW:                                                        │
│ ─────────────────────────────                                       │
│                                                                      │
│                  ┌─────────────┐                                    │
│                  │ %3 = a > b? │                                    │
│                  └──────┬──────┘                                    │
│                         │                                           │
│              ┌──────────┴──────────┐                                │
│              │ condbr              │                                │
│         true │                     │ false                          │
│              ▼                     ▼                                │
│     ┌─────────────┐       ┌─────────────┐                          │
│     │ %5 = a      │       │ %6 = b      │                          │
│     │ br(end, %5) │       │ br(end, %6) │                          │
│     └──────┬──────┘       └──────┬──────┘                          │
│            │                     │                                  │
│            └─────────┬───────────┘                                  │
│                      ▼                                              │
│             ┌─────────────┐                                         │
│             │ end:        │                                         │
│             │ %7 = result │                                         │
│             └─────────────┘                                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Example 3: Function Definition

Let's trace `fn add(a: u32, b: u32) u32 { return a + b; }`:

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXAMPLE: fn add(a: u32, b: u32) u32 { return a + b; }              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ This generates ZIR at TWO levels:                                   │
│                                                                      │
│ LEVEL 1: Function Declaration (at file scope)                       │
│ ─────────────────────────────                                       │
│                                                                      │
│   %1 = declaration("add")     // Declare that "add" exists         │
│   %2 = func(...)              // Function details                  │
│                                                                      │
│ LEVEL 2: Function Body (inside the function)                        │
│ ─────────────────────────────                                       │
│                                                                      │
│   %10 = block {               // Function body block               │
│       %11 = param(0)          // First parameter (a)               │
│       %12 = param(1)          // Second parameter (b)              │
│       %13 = add(%11, %12)     // a + b                             │
│       %14 = ret(%13)          // return the result                 │
│   }                                                                  │
│                                                                      │
│ WHAT EACH INSTRUCTION MEANS:                                        │
│ ─────────────────────────────                                       │
│                                                                      │
│   param(0)                                                          │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ "Give me the first parameter that was passed to this        │  │
│   │  function. I don't know its type yet (that's for Sema),    │  │
│   │  but I know it's parameter number 0."                       │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│   param(1)                                                          │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ "Give me the second parameter (index 1)."                   │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│   add(%11, %12)                                                     │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ "Add the values from instructions 11 and 12 together.       │  │
│   │  I don't know if they're u32, i64, or floats - Sema will   │  │
│   │  figure that out and pick the right machine instruction."  │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│   ret(%13)                                                          │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ "Return from this function with the value from              │  │
│   │  instruction 13. Sema will verify it matches the declared  │  │
│   │  return type (u32)."                                        │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Example 4: Loop

Let's trace a while loop:

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXAMPLE: while (i < 10) { sum += i; i += 1; }                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ZIR STRUCTURE:                                                      │
│                                                                      │
│   loop_block: {                                                     │
│       // 1. Check condition                                         │
│       %1 = load("i")                                               │
│       %2 = int(10)                                                 │
│       %3 = cmp_lt(%1, %2)       // i < 10?                         │
│                                                                      │
│       // 2. Branch based on condition                               │
│       %4 = condbr(%3)                                              │
│            │                                                        │
│            ├──► continue (condition true):                         │
│            │       // Loop body                                    │
│            │       %5 = load("sum")                                │
│            │       %6 = load("i")                                  │
│            │       %7 = add(%5, %6)                                │
│            │       %8 = store("sum", %7)   // sum += i             │
│            │                                                        │
│            │       %9 = load("i")                                  │
│            │       %10 = int(1)                                    │
│            │       %11 = add(%9, %10)                              │
│            │       %12 = store("i", %11)   // i += 1               │
│            │                                                        │
│            │       %13 = repeat(loop_block) // Jump back to start  │
│            │                                                        │
│            └──► break (condition false):                           │
│                    %14 = break(loop_block)  // Exit the loop       │
│   }                                                                  │
│                                                                      │
│ VISUAL FLOW:                                                        │
│                                                                      │
│   ┌──────────────────────────────────────────────┐                 │
│   │                                              │                 │
│   │    ┌─────────────────┐                       │                 │
│   └───►│  i < 10?        │                       │                 │
│        └────────┬────────┘                       │                 │
│                 │                                │                 │
│        ┌───────┴───────┐                        │                 │
│        │ true          │ false                  │                 │
│        ▼               ▼                        │                 │
│   ┌─────────┐    ┌──────────┐                  │                 │
│   │sum += i │    │  EXIT    │                  │                 │
│   │i += 1   │    │  LOOP    │                  │                 │
│   └────┬────┘    └──────────┘                  │                 │
│        │                                        │                 │
│        └────────────────────────────────────────┘                 │
│              (repeat - jump back)                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 6: How AstGen Walks the Tree

### The Main Pattern: Recursive Descent

AstGen uses the same pattern as the parser - functions call other functions:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ASTGEN RECURSIVE PATTERN                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ The main function is `expr()` - it handles ANY expression:         │
│                                                                      │
│   fn expr(node) -> ZirInstruction {                                │
│       switch (node.type) {                                         │
│           .add => {                                                │
│               // First, generate ZIR for left side                 │
│               lhs = expr(node.left);   // RECURSE!                │
│                                                                      │
│               // Then, generate ZIR for right side                 │
│               rhs = expr(node.right);  // RECURSE!                │
│                                                                      │
│               // Finally, generate the add instruction             │
│               return addInstruction(.add, lhs, rhs);               │
│           },                                                        │
│                                                                      │
│           .number => {                                             │
│               // Base case - no recursion needed                   │
│               return addInstruction(.int, node.value);             │
│           },                                                        │
│                                                                      │
│           .if_expr => {                                            │
│               cond = expr(node.condition);  // RECURSE             │
│               then = expr(node.then_body);  // RECURSE             │
│               els = expr(node.else_body);   // RECURSE             │
│               return addInstruction(.condbr, cond, then, els);     │
│           },                                                        │
│                                                                      │
│           // ... many more cases                                    │
│       }                                                             │
│   }                                                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Trace: Processing `(1 + 2) * 3`

```
┌─────────────────────────────────────────────────────────────────────┐
│ TRACE: (1 + 2) * 3                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ AST:          *                                                     │
│              / \                                                     │
│             +   3                                                   │
│            / \                                                       │
│           1   2                                                     │
│                                                                      │
│ EXECUTION:                                                          │
│                                                                      │
│ expr( * ) called                                                    │
│ │                                                                   │
│ │  "I need to process a multiply. Let me get my operands..."       │
│ │                                                                   │
│ ├──► expr( + ) called  // Get left operand                         │
│ │    │                                                              │
│ │    │  "I need to process an add. Let me get MY operands..."      │
│ │    │                                                              │
│ │    ├──► expr( 1 ) called  // Get left operand                    │
│ │    │    │                                                        │
│ │    │    │  "This is just a number. Easy!"                        │
│ │    │    │  EMIT: %1 = int(1)                                     │
│ │    │    │  return %1                                             │
│ │    │    │                                                        │
│ │    │◄───┘                                                        │
│ │    │                                                              │
│ │    ├──► expr( 2 ) called  // Get right operand                   │
│ │    │    │                                                        │
│ │    │    │  "This is just a number. Easy!"                        │
│ │    │    │  EMIT: %2 = int(2)                                     │
│ │    │    │  return %2                                             │
│ │    │    │                                                        │
│ │    │◄───┘                                                        │
│ │    │                                                              │
│ │    │  "Now I have both operands: %1 and %2"                      │
│ │    │  EMIT: %3 = add(%1, %2)                                     │
│ │    │  return %3                                                  │
│ │    │                                                              │
│ │◄───┘                                                              │
│ │                                                                   │
│ ├──► expr( 3 ) called  // Get right operand                        │
│ │    │                                                              │
│ │    │  "This is just a number. Easy!"                              │
│ │    │  EMIT: %4 = int(3)                                          │
│ │    │  return %4                                                   │
│ │    │                                                              │
│ │◄───┘                                                              │
│ │                                                                   │
│ │  "Now I have both operands: %3 and %4"                           │
│ │  EMIT: %5 = mul(%3, %4)                                          │
│ │  return %5                                                        │
│                                                                      │
│ FINAL ZIR:                                                          │
│   %1 = int(1)                                                       │
│   %2 = int(2)                                                       │
│   %3 = add(%1, %2)     // 1 + 2                                    │
│   %4 = int(3)                                                       │
│   %5 = mul(%3, %4)     // (1 + 2) * 3                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 7: Source Location Tracking

### Why Track Locations?

When there's an error, we need to tell the user WHERE:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ERROR MESSAGES NEED LOCATION INFO                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ BAD error message:                                                  │
│   "Error: type mismatch"                                            │
│   (Where?? In which file? Which line?)                             │
│                                                                      │
│ GOOD error message:                                                 │
│   "Error: type mismatch"                                            │
│   " --> src/main.zig:42:15"                                        │
│   " |"                                                              │
│   "42 |     const x: u32 = "hello";"                               │
│   " |                   ^^^^^^^ expected 'u32', found string"     │
│                                                                      │
│ To produce good errors, ZIR must remember where each instruction   │
│ came from in the source code!                                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How Locations are Stored

```
┌─────────────────────────────────────────────────────────────────────┐
│ SOURCE LOCATION IN ZIR                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Each ZIR instruction can reference the AST node it came from:      │
│                                                                      │
│   ZIR Instruction {                                                 │
│       tag: .add,                                                    │
│       data: {                                                       │
│           src_node: 47,    // ← "I came from AST node 47"          │
│           lhs: %3,                                                  │
│           rhs: %5,                                                  │
│       }                                                              │
│   }                                                                  │
│                                                                      │
│ AST node 47 knows its token, and tokens know their position:       │
│                                                                      │
│   AST Node 47 {                                                     │
│       tag: .add,                                                    │
│       main_token: 123,     // ← The "+" token                      │
│   }                                                                  │
│                                                                      │
│   Token 123 {                                                       │
│       tag: .plus,                                                   │
│       start: 1547,         // ← Byte position in source file       │
│   }                                                                  │
│                                                                      │
│ Chain: ZIR instruction → AST node → Token → Source position        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 8: The String Table

### Why a String Table?

Identifiers and strings appear many times. Instead of copying them, we store them once:

```
┌─────────────────────────────────────────────────────────────────────┐
│ STRING TABLE OPTIMIZATION                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Code with repeated identifiers:                                     │
│                                                                      │
│   fn calculate(value: i32) i32 {                                   │
│       const temp = value * 2;                                      │
│       return temp + value;                                         │
│   }                                                                  │
│                                                                      │
│ WITHOUT string table (wasteful):                                    │
│                                                                      │
│   Instruction 1: { name: "calculate", ... }   // 9 bytes           │
│   Instruction 2: { name: "value", ... }       // 5 bytes           │
│   Instruction 3: { name: "i32", ... }         // 3 bytes           │
│   Instruction 4: { name: "i32", ... }         // 3 bytes DUPLICATE│
│   Instruction 5: { name: "temp", ... }        // 4 bytes           │
│   Instruction 6: { name: "value", ... }       // 5 bytes DUPLICATE│
│   Instruction 7: { name: "temp", ... }        // 4 bytes DUPLICATE│
│   Instruction 8: { name: "value", ... }       // 5 bytes DUPLICATE│
│                                                                      │
│ WITH string table (efficient):                                      │
│                                                                      │
│   String Table:                                                     │
│   ┌─────┬─────────────────────────────────────┐                    │
│   │  0  │  \0                                 │ (empty string)     │
│   │  1  │  c a l c u l a t e \0              │                     │
│   │ 11  │  v a l u e \0                      │                     │
│   │ 17  │  i 3 2 \0                          │                     │
│   │ 21  │  t e m p \0                        │                     │
│   └─────┴─────────────────────────────────────┘                    │
│                                                                      │
│   Instructions (just store index):                                  │
│   Instruction 1: { name_index: 1, ... }   // "calculate"           │
│   Instruction 2: { name_index: 11, ... }  // "value"               │
│   Instruction 3: { name_index: 17, ... }  // "i32"                 │
│   Instruction 4: { name_index: 17, ... }  // "i32" (same index!)  │
│   Instruction 5: { name_index: 21, ... }  // "temp"                │
│   Instruction 6: { name_index: 11, ... }  // "value" (same index!)│
│   ...                                                               │
│                                                                      │
│ Memory saved by not duplicating strings!                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 9: Putting It All Together

### Complete Example: Full Function

Let's trace a complete function through AstGen:

```zig
fn max(a: i32, b: i32) i32 {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}
```

```
┌─────────────────────────────────────────────────────────────────────┐
│ COMPLETE ZIR OUTPUT FOR max() FUNCTION                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ // File-level declaration                                           │
│ %0 = declaration {                                                  │
│     name: "max",                                                    │
│     type: function,                                                 │
│ }                                                                    │
│                                                                      │
│ // Function body                                                    │
│ %1 = func {                                                         │
│     params: [                                                       │
│         { name: "a", type_expr: "i32" },                           │
│         { name: "b", type_expr: "i32" },                           │
│     ],                                                               │
│     return_type_expr: "i32",                                        │
│     body: %2,                                                       │
│ }                                                                    │
│                                                                      │
│ // The actual body block                                            │
│ %2 = block {                                                        │
│     // Get parameters                                               │
│     %3 = param(0)              // a                                │
│     %4 = param(1)              // b                                │
│                                                                      │
│     // Evaluate condition: a > b                                   │
│     %5 = cmp_gt(%3, %4)                                            │
│                                                                      │
│     // Conditional branch                                           │
│     %6 = condbr(%5, then_body: %7, else_body: %8)                  │
│                                                                      │
│     // Then branch: return a                                        │
│     %7 = block {                                                    │
│         %9 = ret(%3)           // return a                         │
│     }                                                                │
│                                                                      │
│     // Else branch: return b                                        │
│     %8 = block {                                                    │
│         %10 = ret(%4)          // return b                         │
│     }                                                                │
│ }                                                                    │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ WHAT SEMA WILL DO WITH THIS:                                        │
│                                                                      │
│ 1. See param(0), param(1) → look up that they're i32               │
│ 2. See cmp_gt → verify both operands are comparable                │
│ 3. See ret(%3) → verify i32 matches return type                    │
│ 4. See ret(%4) → verify i32 matches return type                    │
│ 5. If all checks pass → generate typed AIR                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 10: The Big Picture

### Where ZIR Fits

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE COMPLETE COMPILATION PIPELINE                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                     SOURCE CODE                              │  │
│   │         fn add(a: u32, b: u32) u32 { return a+b; }          │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                      TOKENIZER                               │  │
│   │  Breaks into: [fn] [add] [(] [a] [:] [u32] ...              │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                        PARSER                                │  │
│   │  Builds tree structure (AST)                                 │  │
│   │  Knows: syntax structure, operator precedence                │  │
│   │  Doesn't know: types, validity                              │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                       ASTGEN                                 │  │
│   │  Converts tree → linear instructions (ZIR)                  │  │
│   │  Knows: execution order, instruction sequence               │  │
│   │  Doesn't know: types, sizes, validity    ◄─── YOU ARE HERE │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                        SEMA                                  │  │
│   │  Type checks and produces typed AIR                         │  │
│   │  Knows: types, sizes, validity                              │  │
│   │  Catches: type errors, undefined variables                  │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                      CODEGEN                                 │  │
│   │  Generates actual machine code                              │  │
│   │  Knows: CPU instructions, registers, memory layout          │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                    MACHINE CODE                              │  │
│   │           mov rax, rdi                                      │  │
│   │           add rax, rsi                                      │  │
│   │           ret                                               │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Scope System

AstGen uses a sophisticated scope system to track identifiers. There are seven scope types:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ASTGEN SCOPE TYPES                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. Scope.Top           File-level scope (the root)                 │
│                                                                      │
│ 2. GenZir              Block-level state tracking                  │
│                        Tracks current block's instructions          │
│                                                                      │
│ 3. Scope.Namespace     Unordered declaration sets                  │
│                        For structs, enums, etc.                     │
│                                                                      │
│ 4. Scope.LocalVal      Individual identifier bindings              │
│    Scope.LocalPtr      (value vs pointer semantics)                │
│                                                                      │
│ 5. Scope.Defer         Defer/errdefer tracking                     │
│                        Knows what to run on scope exit             │
│                                                                      │
│ When you reference a variable, AstGen walks UP through scopes      │
│ until it finds the definition - this is how shadowing works.       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### String Interning

All strings in ZIR are interned into a single `string_bytes` array and referenced by offset:

```
┌─────────────────────────────────────────────────────────────────────┐
│ STRING INTERNING                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Instead of:                                                          │
│   instruction1 { name: "add" }      ← 3 bytes                       │
│   instruction2 { name: "add" }      ← 3 more bytes (duplicate!)     │
│   instruction3 { name: "multiply" } ← 8 bytes                       │
│                                                                      │
│ ZIR stores:                                                          │
│   string_bytes: "add\0multiply\0"   ← All strings together          │
│                  ↑    ↑                                              │
│                  0    4                                              │
│                                                                      │
│   instruction1 { name_offset: 0 }   ← Just an integer               │
│   instruction2 { name_offset: 0 }   ← Same offset = same string     │
│   instruction3 { name_offset: 4 }   ← Points to "multiply"          │
│                                                                      │
│ Benefits:                                                            │
│   • Deduplication is automatic                                      │
│   • Comparison is just integer equality                             │
│   • After ZIR is built, the AST and source can be freed            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Summary: What ZIR Achieves

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIR KEY POINTS                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. LINEARIZES THE AST                                               │
│    Tree structure → Sequential instructions                         │
│    Easier to process, closer to how CPUs work                      │
│                                                                      │
│ 2. UNTYPED BY DESIGN                                                │
│    No type information embedded                                     │
│    Enables caching, generics, lazy analysis                        │
│                                                                      │
│ 3. PRESERVES SOURCE LOCATIONS                                       │
│    Every instruction knows where it came from                       │
│    Enables precise error messages                                   │
│                                                                      │
│ 4. ONE PER SOURCE FILE                                              │
│    Each .zig file gets its own ZIR                                 │
│    Can be cached to disk for faster rebuilds                       │
│                                                                      │
│ 5. REFERENCE-BASED                                                  │
│    Instructions refer to each other by number (%1, %2, ...)        │
│    Creates a directed graph of dependencies                        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Dump the ZIR for any Zig file to see how your code is represented:

```bash
# Dump ZIR for a file
zig ast-check -t your_file.zig
```

This is invaluable for understanding how Zig transforms your high-level code into intermediate representation.

---

## Further Reading

For deeper exploration of ZIR and AstGen:

- **[Zig AstGen: AST => ZIR](https://mitchellh.com/zig/astgen)** by Mitchell Hashimoto - Comprehensive walkthrough of how AST nodes become ZIR instructions.

- **[Zig GitHub Wiki Glossary](https://github.com/ziglang/zig/wiki/Glossary)** - Official definitions including ZIR's ~400 instruction types.

- **Source Code**: [`src/AstGen.zig`](https://github.com/ziglang/zig/blob/master/src/AstGen.zig) and [`lib/std/zig/Zir.zig`](https://github.com/ziglang/zig/blob/master/lib/std/zig/Zir.zig) - The implementations.

---

## Conclusion

ZIR is the bridge between the human-readable AST and the type-checked AIR. By keeping ZIR untyped, Zig enables:

- **Caching**: Save ZIR to disk, skip parsing on rebuild
- **Generics**: Same ZIR instantiated with different types
- **Lazy Analysis**: Only type-check what's actually used
- **Incremental Compilation**: Change one file, don't re-analyze everything

In the next article, we'll dive into **Sema** (Semantic Analysis), where ZIR is transformed into typed AIR and the real type checking happens.

---

**Previous**: [Part 3: Parser and AST](./03-parser-ast.md)
**Next**: [Part 5: Semantic Analysis](./05-sema.md)

**Series Index**:
1. [Bootstrap Process](./01-bootstrap-process.md)
2. [Tokenizer](./02-tokenizer.md)
3. [Parser and AST](./03-parser-ast.md)
4. **ZIR Generation** (this article)
5. [Semantic Analysis](./05-sema.md)
6. [AIR and Code Generation](./06-air-codegen.md)
7. [Linking](./07-linking.md)
