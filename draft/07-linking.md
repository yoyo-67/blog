# Zig Compiler Internals Part 7: Linking

*From object files to executables - the final step*

---

## Introduction

You've written your code, it's been parsed, type-checked, and turned into machine code. But you still don't have a program you can run! The **linker** is the final piece of the puzzle - it takes all the pieces and combines them into a single executable file.

This article explains:
- What linking is and why we need it
- What object files contain
- How symbols and relocations work
- Why Zig has its own linkers
- How different executable formats work

---

## Part 1: What is Linking?

### The Problem: Code in Pieces

When you compile a program, each source file becomes an **object file**. But these pieces can't run on their own:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE PROBLEM: SCATTERED CODE                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Your project:                                                        │
│                                                                      │
│   main.zig          utils.zig         math.zig                      │
│   ─────────         ──────────        ─────────                     │
│   fn main() {       fn helper() {     fn add() {                    │
│       helper();         ...               ...                       │
│       add();        }                 }                             │
│   }                                                                  │
│                                                                      │
│ After compilation (separate object files):                          │
│                                                                      │
│   main.o            utils.o           math.o                        │
│   ─────────         ──────────        ─────────                     │
│   main:             helper:           add:                          │
│     call ???        ...               ...                           │
│     call ???                                                        │
│        ↑                                                            │
│        │                                                            │
│   "I need to call helper and add,                                   │
│    but I don't know where they are!"                                │
│                                                                      │
│ Each object file is incomplete - it has HOLES where it needs        │
│ to reference things from other files.                               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Solution: Linking

The linker combines all pieces and fills in the holes:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE SOLUTION: LINKING                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   main.o + utils.o + math.o                                         │
│                 │                                                    │
│                 ▼                                                    │
│           ┌──────────┐                                              │
│           │  LINKER  │                                              │
│           └────┬─────┘                                              │
│                │                                                     │
│                ▼                                                     │
│   ┌─────────────────────────────────────────┐                       │
│   │          EXECUTABLE                      │                       │
│   │                                          │                       │
│   │   main:           (at address 0x1000)   │                       │
│   │     call 0x2000   ← filled in!          │                       │
│   │     call 0x3000   ← filled in!          │                       │
│   │                                          │                       │
│   │   helper:         (at address 0x2000)   │                       │
│   │     ...                                  │                       │
│   │                                          │                       │
│   │   add:            (at address 0x3000)   │                       │
│   │     ...                                  │                       │
│   │                                          │                       │
│   └─────────────────────────────────────────┘                       │
│                                                                      │
│ The linker:                                                         │
│   1. Puts all the code together                                     │
│   2. Assigns addresses to everything                                │
│   3. Fills in all the holes                                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### What the Linker Does (Summary)

```
┌─────────────────────────────────────────────────────────────────────┐
│ LINKER RESPONSIBILITIES                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. GATHER INPUTS                                                    │
│    • Object files (.o) from your code                              │
│    • Static libraries (.a) you're using                            │
│    • Shared libraries (.so/.dylib/.dll) to link against           │
│                                                                      │
│ 2. RESOLVE SYMBOLS                                                  │
│    • "main.o needs 'helper'" → found in utils.o                    │
│    • "main.o needs 'printf'" → found in libc.so                    │
│    • Report errors for undefined symbols                           │
│                                                                      │
│ 3. ARRANGE IN MEMORY                                                │
│    • Put all code together in one section                          │
│    • Put all data together in another section                      │
│    • Assign virtual addresses to everything                        │
│                                                                      │
│ 4. FIX UP REFERENCES (Relocations)                                 │
│    • Replace "call ???" with "call 0x2000"                        │
│    • Replace "load ???" with "load 0x5000"                        │
│                                                                      │
│ 5. PRODUCE OUTPUT                                                   │
│    • Write executable file in proper format                        │
│    • Add headers the OS needs to load it                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: What's Inside an Object File?

### Object File Structure

An object file contains several pieces of information:

```
┌─────────────────────────────────────────────────────────────────────┐
│ OBJECT FILE ANATOMY                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │                        OBJECT FILE                               ││
│ │                                                                   ││
│ │  ┌─────────────────────────────────────────────────────────────┐││
│ │  │ HEADER                                                       │││
│ │  │ • File format (ELF, MachO, COFF)                            │││
│ │  │ • Target architecture (x86_64, ARM64)                       │││
│ │  │ • Number of sections                                        │││
│ │  └─────────────────────────────────────────────────────────────┘││
│ │                                                                   ││
│ │  ┌─────────────────────────────────────────────────────────────┐││
│ │  │ CODE SECTION (.text)                                        │││
│ │  │ • Machine code for all functions                            │││
│ │  │ • Contains "holes" where external refs go                   │││
│ │  └─────────────────────────────────────────────────────────────┘││
│ │                                                                   ││
│ │  ┌─────────────────────────────────────────────────────────────┐││
│ │  │ DATA SECTION (.data)                                        │││
│ │  │ • Initialized global variables                              │││
│ │  │ • Constant values                                           │││
│ │  └─────────────────────────────────────────────────────────────┘││
│ │                                                                   ││
│ │  ┌─────────────────────────────────────────────────────────────┐││
│ │  │ SYMBOL TABLE                                                 │││
│ │  │ • List of functions/variables this file DEFINES             │││
│ │  │ • List of functions/variables this file NEEDS               │││
│ │  └─────────────────────────────────────────────────────────────┘││
│ │                                                                   ││
│ │  ┌─────────────────────────────────────────────────────────────┐││
│ │  │ RELOCATION TABLE                                            │││
│ │  │ • "At offset 0x10, fill in address of 'helper'"            │││
│ │  │ • "At offset 0x20, fill in address of 'global_var'"        │││
│ │  └─────────────────────────────────────────────────────────────┘││
│ │                                                                   ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Example: What's in main.o

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXAMPLE: main.o                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Source code (main.zig):                                             │
│                                                                      │
│   const std = @import("std");                                       │
│   extern fn helper() void;      // Defined elsewhere                │
│                                                                      │
│   pub fn main() void {                                              │
│       helper();                                                     │
│       std.debug.print("Hello\n", .{});                             │
│   }                                                                  │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ Object file (main.o) contains:                                      │
│                                                                      │
│ SYMBOL TABLE:                                                       │
│ ┌──────────────┬────────────────┬─────────────────────────────────┐│
│ │ Name         │ Type           │ Notes                           ││
│ ├──────────────┼────────────────┼─────────────────────────────────┤│
│ │ main         │ DEFINED        │ At offset 0x0000 in .text       ││
│ │ helper       │ UNDEFINED      │ Need to find this elsewhere!    ││
│ │ std.debug... │ UNDEFINED      │ Need to find this elsewhere!    ││
│ └──────────────┴────────────────┴─────────────────────────────────┘│
│                                                                      │
│ CODE SECTION (.text):                                               │
│ ┌──────────┬──────────────────────────────────────────────────────┐│
│ │ Offset   │ Machine Code                                         ││
│ ├──────────┼──────────────────────────────────────────────────────┤│
│ │ 0x0000   │ push rbp          ; main function starts            ││
│ │ 0x0001   │ mov rbp, rsp                                        ││
│ │ 0x0004   │ call 0x00000000   ; ← HOLE! Address unknown         ││
│ │ 0x0009   │ ...               ; rest of main                    ││
│ └──────────┴──────────────────────────────────────────────────────┘│
│                                                                      │
│ RELOCATION TABLE:                                                   │
│ ┌──────────┬──────────────┬─────────────────────────────────────┐  │
│ │ Offset   │ Symbol       │ Meaning                             │  │
│ ├──────────┼──────────────┼─────────────────────────────────────┤  │
│ │ 0x0005   │ helper       │ "Put address of 'helper' here"     │  │
│ └──────────┴──────────────┴─────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 3: Symbols - The Names of Things

### What is a Symbol?

A **symbol** is a name that refers to something in your code:

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT ARE SYMBOLS?                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Symbols are names for:                                              │
│                                                                      │
│   • Functions        fn add(a: i32, b: i32) i32 { ... }            │
│                          ↑                                          │
│                      Symbol: "add"                                  │
│                                                                      │
│   • Global variables  var counter: u32 = 0;                        │
│                           ↑                                         │
│                       Symbol: "counter"                             │
│                                                                      │
│   • Constants         const MAX_SIZE: usize = 1024;                │
│                             ↑                                       │
│                         Symbol: "MAX_SIZE"                          │
│                                                                      │
│ Each symbol has:                                                    │
│   • A name (like "add" or "counter")                               │
│   • A type (function, variable, constant)                          │
│   • A location (address once linked)                               │
│   • Visibility (local, global, exported)                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Defined vs Undefined Symbols

```
┌─────────────────────────────────────────────────────────────────────┐
│ DEFINED vs UNDEFINED SYMBOLS                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ DEFINED: "I have this"                                              │
│ ─────────────────────────                                           │
│                                                                      │
│   // In math.zig                                                    │
│   pub fn add(a: i32, b: i32) i32 {                                 │
│       return a + b;                                                 │
│   }                                                                  │
│                                                                      │
│   math.o defines symbol "add"                                       │
│   • The code for add() is IN this file                             │
│   • It has a specific offset (e.g., 0x100)                         │
│                                                                      │
│ UNDEFINED: "I need this"                                            │
│ ─────────────────────────                                           │
│                                                                      │
│   // In main.zig                                                    │
│   const math = @import("math.zig");                                │
│                                                                      │
│   pub fn main() void {                                              │
│       const result = math.add(5, 3);  // Using add()               │
│   }                                                                  │
│                                                                      │
│   main.o has undefined symbol "add"                                 │
│   • main.o calls add() but doesn't have the code                   │
│   • The linker must find it elsewhere                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Symbol Resolution

The linker matches undefined symbols to defined symbols:

```
┌─────────────────────────────────────────────────────────────────────┐
│ SYMBOL RESOLUTION                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ STEP 1: Collect all symbols from all object files                  │
│                                                                      │
│   main.o:                                                           │
│     DEFINES: main                                                   │
│     NEEDS: add, printf                                             │
│                                                                      │
│   math.o:                                                           │
│     DEFINES: add, subtract, multiply                               │
│     NEEDS: (nothing)                                                │
│                                                                      │
│   libc.so:                                                          │
│     DEFINES: printf, malloc, free, ...                             │
│     NEEDS: (nothing)                                                │
│                                                                      │
│ STEP 2: Match needs to definitions                                 │
│                                                                      │
│   main.o needs "add"     →  Found in math.o ✓                      │
│   main.o needs "printf"  →  Found in libc.so ✓                     │
│                                                                      │
│ STEP 3: Report errors for unresolved symbols                       │
│                                                                      │
│   If main.o needs "foo" but no one defines it:                     │
│                                                                      │
│   error: undefined reference to 'foo'                              │
│   >>> main.o: in function 'main'                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 4: Relocations - Filling in the Holes

### What are Relocations?

When code is compiled, we don't know final addresses yet. Relocations tell the linker what to fix:

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT ARE RELOCATIONS?                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Source code:                                                        │
│                                                                      │
│   fn main() void {                                                  │
│       helper();  // Call another function                          │
│   }                                                                  │
│                                                                      │
│ Compiled code (before linking):                                     │
│                                                                      │
│   main:                                                              │
│       call 0x00000000     ; We don't know helper's address yet!    │
│            ↑                                                        │
│            └── This is a PLACEHOLDER (all zeros)                   │
│                                                                      │
│ Relocation entry:                                                   │
│                                                                      │
│   "At offset 0x0001, insert the address of symbol 'helper'"        │
│                                                                      │
│ After linking (addresses known):                                   │
│                                                                      │
│   main:       (at address 0x1000)                                  │
│       call 0x00002000     ; Now we know: helper is at 0x2000!      │
│            ↑                                                        │
│            └── FILLED IN by linker                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Types of Relocations

Different code patterns need different relocation types:

```
┌─────────────────────────────────────────────────────────────────────┐
│ RELOCATION TYPES                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. ABSOLUTE                                                         │
│    ─────────────────────                                            │
│    "Put the full address here"                                     │
│                                                                      │
│    mov rax, 0x0000000000000000   ; Load address of global_var     │
│              ↑                                                      │
│              Put absolute address here (64 bits)                   │
│                                                                      │
│ 2. PC-RELATIVE (Program Counter Relative)                          │
│    ─────────────────────                                            │
│    "Put the distance from here to there"                           │
│                                                                      │
│    call 0x00000000               ; Call helper                     │
│         ↑                                                           │
│         Put (helper_addr - current_addr) here                      │
│                                                                      │
│    Why PC-relative?                                                 │
│    • Works regardless of where code is loaded                      │
│    • Essential for position-independent code (shared libraries)   │
│    • Smaller encoding (32 bits instead of 64)                      │
│                                                                      │
│ 3. GOT-RELATIVE (for shared library symbols)                       │
│    ─────────────────────                                            │
│    "Look up the address in the Global Offset Table"                │
│                                                                      │
│    mov rax, [rip + GOT_OFFSET]   ; Load from GOT                   │
│                                                                      │
│    (More on GOT later!)                                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Relocation in Action

```
┌─────────────────────────────────────────────────────────────────────┐
│ RELOCATION EXAMPLE                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ BEFORE LINKING:                                                     │
│                                                                      │
│ main.o (.text section at offset 0):                                │
│ ┌─────────┬──────────────────────────────────────────────────────┐ │
│ │ Offset  │ Bytes                    Meaning                     │ │
│ ├─────────┼──────────────────────────────────────────────────────┤ │
│ │ 0x0000  │ 55                       push rbp                    │ │
│ │ 0x0001  │ 48 89 e5                 mov rbp, rsp                │ │
│ │ 0x0004  │ e8 00 00 00 00           call <PLACEHOLDER>          │ │
│ │         │    ↑↑↑↑↑↑↑↑↑↑                                        │ │
│ │         │    These zeros will be filled in                     │ │
│ │ 0x0009  │ ...                      rest of function            │ │
│ └─────────┴──────────────────────────────────────────────────────┘ │
│                                                                      │
│ Relocation: PC-relative at offset 0x0005, target: "helper"         │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ LINKER ASSIGNS ADDRESSES:                                           │
│                                                                      │
│   main:   at 0x1000                                                │
│   helper: at 0x2000                                                │
│                                                                      │
│ LINKER CALCULATES OFFSET:                                           │
│                                                                      │
│   call instruction is at: 0x1004                                   │
│   next instruction is at: 0x1009 (call is 5 bytes)                │
│   helper is at: 0x2000                                             │
│   offset = 0x2000 - 0x1009 = 0x0FF7                                │
│                                                                      │
│ AFTER LINKING:                                                      │
│ ┌─────────┬──────────────────────────────────────────────────────┐ │
│ │ Address │ Bytes                    Meaning                     │ │
│ ├─────────┼──────────────────────────────────────────────────────┤ │
│ │ 0x1000  │ 55                       push rbp                    │ │
│ │ 0x1001  │ 48 89 e5                 mov rbp, rsp                │ │
│ │ 0x1004  │ e8 f7 0f 00 00           call 0x2000                 │ │
│ │         │    ↑↑↑↑↑↑↑↑↑↑                                        │ │
│ │         │    FILLED IN: 0x00000FF7 (little-endian)            │ │
│ │ 0x1009  │ ...                      rest of function            │ │
│ └─────────┴──────────────────────────────────────────────────────┘ │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Static vs Dynamic Linking

### Two Ways to Link Libraries

```
┌─────────────────────────────────────────────────────────────────────┐
│ STATIC vs DYNAMIC LINKING                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ STATIC LINKING                                                      │
│ ──────────────                                                      │
│ Copy library code INTO your executable                             │
│                                                                      │
│   your_code.o + libfoo.a                                           │
│         │                                                           │
│         ▼                                                           │
│   ┌───────────────────────┐                                        │
│   │     your_program      │                                        │
│   │                       │                                        │
│   │  ┌─────────────────┐  │                                        │
│   │  │   Your code     │  │                                        │
│   │  ├─────────────────┤  │                                        │
│   │  │   libfoo code   │  │  ← COPIED INTO executable              │
│   │  └─────────────────┘  │                                        │
│   └───────────────────────┘                                        │
│                                                                      │
│   ✓ Self-contained (no dependencies at runtime)                    │
│   ✓ Faster startup (no loading libraries)                         │
│   ✗ Larger executable                                              │
│   ✗ Can't update library without recompiling                      │
│   ✗ Each program has its own copy                                 │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ DYNAMIC LINKING                                                     │
│ ───────────────                                                     │
│ Reference library code, load at runtime                            │
│                                                                      │
│   your_code.o + libfoo.so (reference only)                         │
│         │                                                           │
│         ▼                                                           │
│   ┌───────────────────────┐       ┌─────────────────┐              │
│   │     your_program      │       │   libfoo.so     │              │
│   │                       │       │                 │              │
│   │  ┌─────────────────┐  │       │  foo_function   │              │
│   │  │   Your code     │  │       │  bar_function   │              │
│   │  ├─────────────────┤  │       │  ...            │              │
│   │  │  "I need foo"   │──┼──────►│                 │              │
│   │  └─────────────────┘  │       └─────────────────┘              │
│   └───────────────────────┘              ↑                          │
│                                          │                          │
│                              Loaded at runtime                      │
│                                                                      │
│   ✓ Smaller executable                                             │
│   ✓ Library can be updated without recompiling                    │
│   ✓ Multiple programs share one copy in memory                    │
│   ✗ Requires library present at runtime                           │
│   ✗ Slightly slower (indirection through GOT/PLT)                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### GOT and PLT: Dynamic Linking Magic

Dynamic linking needs special machinery to work:

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHY GOT AND PLT?                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ THE PROBLEM:                                                        │
│                                                                      │
│ When you compile your program, you don't know where the shared     │
│ library will be loaded in memory!                                  │
│                                                                      │
│   Your program loaded at: 0x400000                                 │
│   libc.so loaded at:      ??? (could be anywhere!)                 │
│                                                                      │
│ So how can we call printf() if we don't know its address?          │
│                                                                      │
│ THE SOLUTION: Indirection                                           │
│                                                                      │
│   Instead of:   call printf   (direct call, address unknown)       │
│   We do:        call PLT[printf]  (indirect, address in table)     │
│                                                                      │
│ The PLT (Procedure Linkage Table) and GOT (Global Offset Table)    │
│ work together to make this happen.                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How GOT Works

```
┌─────────────────────────────────────────────────────────────────────┐
│ GOT: GLOBAL OFFSET TABLE                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ The GOT is a table of pointers to external data/functions:         │
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ GOT (in your executable's data section)                          ││
│ ├──────────┬──────────────────────────────────────────────────────┤│
│ │ Entry 0  │ 0x00007fff12340000  ← address of printf              ││
│ │ Entry 1  │ 0x00007fff12340100  ← address of malloc              ││
│ │ Entry 2  │ 0x00007fff12350000  ← address of errno (variable)    ││
│ │ ...      │ ...                                                   ││
│ └──────────┴──────────────────────────────────────────────────────┘│
│                                                                      │
│ When your code needs a library symbol:                             │
│                                                                      │
│   // Accessing external variable                                   │
│   mov rax, [GOT + errno_offset]  ; Load address from GOT          │
│   mov eax, [rax]                 ; Load actual value              │
│                                                                      │
│ The dynamic linker fills in GOT entries at load time!              │
│                                                                      │
│   1. OS loads your program                                         │
│   2. OS loads shared libraries                                     │
│   3. Dynamic linker runs                                           │
│   4. Dynamic linker fills GOT with actual addresses                │
│   5. Your program starts running                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How PLT Works

```
┌─────────────────────────────────────────────────────────────────────┐
│ PLT: PROCEDURE LINKAGE TABLE                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ PLT is for calling functions (not data access).                    │
│ It adds lazy binding - resolve address on FIRST call.              │
│                                                                      │
│ Your code:                                                          │
│   call printf@PLT      ; Don't call printf directly                │
│                                                                      │
│ PLT entry for printf:                                              │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ printf@PLT:                                                      ││
│ │     jmp [GOT[printf]]    ; Jump to address in GOT               ││
│ │     push printf_index    ; If GOT not filled, fall through      ││
│ │     jmp resolver         ; Call dynamic linker to resolve       ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
│ FIRST CALL:                                                         │
│ ─────────────                                                       │
│   1. call printf@PLT                                               │
│   2. jmp [GOT[printf]] → GOT contains address of "push" below!    │
│   3. push printf_index                                             │
│   4. jmp resolver                                                  │
│   5. Resolver finds printf in libc.so                              │
│   6. Resolver updates GOT[printf] with real address                │
│   7. Resolver jumps to real printf                                 │
│                                                                      │
│ SECOND CALL (and beyond):                                          │
│ ─────────────                                                       │
│   1. call printf@PLT                                               │
│   2. jmp [GOT[printf]] → GOT now has REAL address!                │
│   3. Directly executes printf (fast!)                              │
│                                                                      │
│ This is "lazy binding" - only resolve symbols when first used.    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 6: Executable File Formats

### Different Platforms, Different Formats

Each operating system has its own executable format:

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXECUTABLE FORMATS BY PLATFORM                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ PLATFORM           FORMAT          FILE EXTENSION                   │
│ ─────────────      ──────────      ────────────────                 │
│ Linux/BSD          ELF             (none) or .so                   │
│ macOS/iOS          Mach-O          (none) or .dylib                │
│ Windows            PE/COFF         .exe or .dll                    │
│ Web Browser        WebAssembly     .wasm                           │
│                                                                      │
│ Each format has:                                                    │
│   • Different header structure                                     │
│   • Different section names                                        │
│   • Different relocation types                                     │
│   • Different dynamic linking mechanism                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### ELF (Linux/BSD)

```
┌─────────────────────────────────────────────────────────────────────┐
│ ELF FORMAT                                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ELF = Executable and Linkable Format                               │
│ Used on: Linux, BSD, PlayStation, many embedded systems            │
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ ELF HEADER                                                       ││
│ │ • Magic: 0x7F 'E' 'L' 'F'                                       ││
│ │ • Class: 32-bit or 64-bit                                       ││
│ │ • Endianness: little or big                                     ││
│ │ • OS/ABI: Linux, FreeBSD, etc.                                  ││
│ │ • Entry point address                                           ││
│ │ • Program header offset                                         ││
│ │ • Section header offset                                         ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ PROGRAM HEADERS (for loading)                                    ││
│ │ • PT_LOAD: segments to load into memory                         ││
│ │ • PT_DYNAMIC: dynamic linking info                              ││
│ │ • PT_INTERP: path to dynamic linker                             ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ SECTIONS                                                         ││
│ │ • .text: executable code                                        ││
│ │ • .rodata: read-only data                                       ││
│ │ • .data: initialized read-write data                            ││
│ │ • .bss: uninitialized data (zeroed)                             ││
│ │ • .symtab: symbol table                                         ││
│ │ • .strtab: string table                                         ││
│ │ • .rela.text: relocations for code                              ││
│ │ • .dynamic: dynamic linking info                                ││
│ │ • .got: global offset table                                     ││
│ │ • .plt: procedure linkage table                                 ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ SECTION HEADERS (for linking/debugging)                          ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Mach-O (macOS/iOS)

```
┌─────────────────────────────────────────────────────────────────────┐
│ MACH-O FORMAT                                                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Mach-O = Mach Object (from NeXT/Mach kernel)                       │
│ Used on: macOS, iOS, watchOS, tvOS                                 │
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ MACH HEADER                                                      ││
│ │ • Magic: 0xFEEDFACE (32-bit) or 0xFEEDFACF (64-bit)             ││
│ │ • CPU type: x86_64, ARM64                                       ││
│ │ • File type: executable, dylib, bundle                          ││
│ │ • Number of load commands                                       ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ LOAD COMMANDS                                                    ││
│ │ • LC_SEGMENT_64: define memory segments                         ││
│ │ • LC_MAIN: entry point                                          ││
│ │ • LC_LOAD_DYLIB: libraries to load                              ││
│ │ • LC_SYMTAB: symbol table info                                  ││
│ │ • LC_DYSYMTAB: dynamic symbol table                             ││
│ │ • LC_CODE_SIGNATURE: code signing                               ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ SEGMENTS                                                         ││
│ │ • __PAGEZERO: null page (catches null pointers)                 ││
│ │ • __TEXT: code and read-only data                               ││
│ │   └── __text section (code)                                     ││
│ │   └── __cstring section (C strings)                             ││
│ │ • __DATA: read-write data                                       ││
│ │   └── __data section                                            ││
│ │   └── __bss section                                             ││
│ │ • __LINKEDIT: linking information                               ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
│ UNIQUE TO MACOS:                                                    │
│ • Code signing is REQUIRED                                         │
│ • Universal binaries (multiple architectures in one file)         │
│ • Two-level namespace (library name + symbol name)                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### PE/COFF (Windows)

```
┌─────────────────────────────────────────────────────────────────────┐
│ PE/COFF FORMAT                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ PE = Portable Executable                                            │
│ COFF = Common Object File Format                                   │
│ Used on: Windows                                                    │
│                                                                      │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ DOS HEADER (for backwards compatibility!)                        ││
│ │ • Magic: "MZ"                                                    ││
│ │ • "This program cannot be run in DOS mode"                      ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ PE SIGNATURE: "PE\0\0"                                           ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ COFF HEADER                                                      ││
│ │ • Machine type: x86, x64, ARM                                   ││
│ │ • Number of sections                                            ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ OPTIONAL HEADER (not actually optional!)                         ││
│ │ • Entry point                                                    ││
│ │ • Image base address                                            ││
│ │ • Section alignment                                             ││
│ │ • Subsystem: console, GUI, driver                               ││
│ │ • Data directories: imports, exports, resources                 ││
│ ├─────────────────────────────────────────────────────────────────┤│
│ │ SECTIONS                                                         ││
│ │ • .text: code                                                    ││
│ │ • .rdata: read-only data                                        ││
│ │ • .data: data                                                    ││
│ │ • .idata: import table                                          ││
│ │ • .edata: export table                                          ││
│ │ • .rsrc: resources (icons, dialogs)                             ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                      │
│ UNIQUE TO WINDOWS:                                                  │
│ • Import libraries (.lib) for DLL linking                         │
│ • Resources embedded in executable                                 │
│ • SEH (Structured Exception Handling)                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 7: Why Zig Has Its Own Linker

### Traditional Approach vs Zig Approach

```
┌─────────────────────────────────────────────────────────────────────┐
│ TRADITIONAL COMPILERS                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Compiler outputs object files, then calls external linker:       │
│                                                                      │
│   source.c → gcc → source.o ─┐                                     │
│                               ├──→ ld (system linker) → executable │
│   other.c → gcc → other.o  ──┘                                     │
│                                                                      │
│   Problems:                                                         │
│   • Need platform-specific linker installed                        │
│   • Cross-compilation requires cross-linker                        │
│   • Less control over output                                       │
│   • Harder to do incremental linking                               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ ZIG'S APPROACH                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Zig has its own linker built-in:                                 │
│                                                                      │
│   source.zig ─┐                                                     │
│               ├──→ zig (compiler + linker) → executable            │
│   other.zig ──┘                                                     │
│                                                                      │
│   Benefits:                                                         │
│   • Cross-compile to ANY target from ANY host                     │
│   • No external tools needed                                       │
│   • Incremental linking for fast rebuilds                         │
│   • Reproducible builds                                            │
│   • Full control over output                                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Zig's Four Linkers

Zig implements linkers for all major platforms:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIG'S LINKER IMPLEMENTATIONS                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. ELF LINKER (src/link/Elf.zig)                                   │
│    • ~159,000 bytes of code                                        │
│    • Targets: Linux, FreeBSD, NetBSD, many embedded                │
│    • Features: dynamic linking, DWARF debug info                   │
│                                                                      │
│ 2. MACH-O LINKER (src/link/MachO.zig)                              │
│    • ~196,000 bytes of code                                        │
│    • Targets: macOS, iOS, watchOS, tvOS                            │
│    • Features: code signing, universal binaries                    │
│                                                                      │
│ 3. COFF LINKER (src/link/Coff.zig)                                 │
│    • ~94,000 bytes of code                                         │
│    • Targets: Windows                                               │
│    • Features: import libraries, resources                         │
│                                                                      │
│ 4. WASM LINKER (src/link/Wasm.zig)                                 │
│    • Targets: Web browsers, WASI                                   │
│    • Features: custom sections, WASI imports                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Incremental Linking

One of Zig's killer features:

```
┌─────────────────────────────────────────────────────────────────────┐
│ INCREMENTAL LINKING                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ TRADITIONAL LINKING:                                                │
│                                                                      │
│   Change one function → Relink entire program                      │
│                                                                      │
│   file1.o ─┐                                                        │
│   file2.o ─┼──→ linker → executable (full rebuild)                │
│   file3.o ─┘                                                        │
│              ↑                                                      │
│         Time: seconds to minutes                                   │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ INCREMENTAL LINKING:                                                │
│                                                                      │
│   Change one function → Update ONLY that function                  │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ EXECUTABLE (with padding for growth)                         │  │
│   │                                                              │  │
│   │ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐            │  │
│   │ │  func1  │ │  func2  │ │  func3  │ │ (empty) │            │  │
│   │ └─────────┘ └─────────┘ └─────────┘ └─────────┘            │  │
│   │                  ↑                                           │  │
│   │                  │                                           │  │
│   │             Patch in place!                                  │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│   How it works:                                                     │
│   1. Leave padding after each function                             │
│   2. When function changes:                                        │
│      a. If new size <= old size + padding: patch in place         │
│      b. If new size > old: allocate new space, redirect calls     │
│                                                                      │
│   Time: milliseconds!                                               │
│                                                                      │
│   This is why `zig build` is so fast during development.           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 8: The Linking Process Step by Step

### Complete Linking Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE LINKING PROCESS                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ STEP 1: GATHER INPUTS                                               │
│ ─────────────────────────────────────────────────                   │
│                                                                      │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐              │
│   │ main.o  │  │ utils.o │  │ libc.a  │  │libm.so  │              │
│   └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘              │
│        │            │            │            │                     │
│        └────────────┴─────┬──────┴────────────┘                    │
│                           ▼                                         │
│                     ┌──────────┐                                    │
│                     │  LINKER  │                                    │
│                     └────┬─────┘                                    │
│                          │                                          │
│                                                                      │
│ STEP 2: BUILD GLOBAL SYMBOL TABLE                                  │
│ ─────────────────────────────────────────────────                   │
│                                                                      │
│   Scan all inputs, collect all symbols:                            │
│                                                                      │
│   ┌──────────────┬────────────────┬─────────────────────────────┐  │
│   │ Symbol       │ Defined In     │ Address (TBD)               │  │
│   ├──────────────┼────────────────┼─────────────────────────────┤  │
│   │ main         │ main.o         │ ???                         │  │
│   │ helper       │ utils.o        │ ???                         │  │
│   │ printf       │ libc.so        │ ??? (dynamic)               │  │
│   │ sqrt         │ libm.so        │ ??? (dynamic)               │  │
│   └──────────────┴────────────────┴─────────────────────────────┘  │
│                                                                      │
│                                                                      │
│ STEP 3: RESOLVE UNDEFINED SYMBOLS                                  │
│ ─────────────────────────────────────────────────                   │
│                                                                      │
│   main.o needs "helper"  → Found in utils.o ✓                      │
│   main.o needs "printf"  → Found in libc.so ✓                      │
│   utils.o needs "sqrt"   → Found in libm.so ✓                      │
│                                                                      │
│   If any symbol not found: ERROR!                                  │
│                                                                      │
│                                                                      │
│ STEP 4: MERGE SECTIONS                                             │
│ ─────────────────────────────────────────────────                   │
│                                                                      │
│   Combine all .text sections:                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ main.o:.text  │ utils.o:.text  │ (from static libs)         │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│   Combine all .data sections:                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │ main.o:.data  │ utils.o:.data  │ (from static libs)         │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│                                                                      │
│ STEP 5: ASSIGN ADDRESSES                                           │
│ ─────────────────────────────────────────────────                   │
│                                                                      │
│   ┌────────────────────────────────────────────┐                   │
│   │ Address      │ Content                     │                   │
│   ├──────────────┼─────────────────────────────┤                   │
│   │ 0x400000     │ ELF header                  │                   │
│   │ 0x401000     │ .text (code)                │                   │
│   │ 0x401000     │   main                      │                   │
│   │ 0x401100     │   helper                    │                   │
│   │ 0x402000     │ .rodata (constants)         │                   │
│   │ 0x403000     │ .data (variables)           │                   │
│   │ 0x404000     │ .bss (zero-init)            │                   │
│   └──────────────┴─────────────────────────────┘                   │
│                                                                      │
│                                                                      │
│ STEP 6: APPLY RELOCATIONS                                          │
│ ─────────────────────────────────────────────────                   │
│                                                                      │
│   For each relocation entry:                                       │
│   1. Look up target symbol's address                               │
│   2. Calculate value (absolute or relative)                        │
│   3. Write to specified offset                                     │
│                                                                      │
│   Before: call 0x00000000   ; placeholder                          │
│   After:  call 0x00000100   ; offset to helper                     │
│                                                                      │
│                                                                      │
│ STEP 7: GENERATE DYNAMIC LINKING INFO                              │
│ ─────────────────────────────────────────────────                   │
│                                                                      │
│   If using shared libraries:                                       │
│   • Create GOT entries for external data                          │
│   • Create PLT entries for external functions                     │
│   • Create .dynamic section with library dependencies             │
│                                                                      │
│                                                                      │
│ STEP 8: WRITE OUTPUT FILE                                          │
│ ─────────────────────────────────────────────────                   │
│                                                                      │
│   • Write file header                                              │
│   • Write program headers (for loading)                            │
│   • Write all sections                                             │
│   • Write section headers (for debugging)                          │
│   • Add code signature (macOS)                                     │
│                                                                      │
│                          ▼                                          │
│                  ┌──────────────┐                                   │
│                  │  executable  │                                   │
│                  └──────────────┘                                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 9: Debug Information

### What is Debug Info?

Debug info connects machine code back to source code:

```
┌─────────────────────────────────────────────────────────────────────┐
│ DEBUG INFORMATION                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ When you run a debugger (gdb, lldb):                               │
│                                                                      │
│   (gdb) break main.zig:42    ← Set breakpoint at LINE 42           │
│   (gdb) print my_variable    ← Show VALUE of variable              │
│   (gdb) backtrace            ← Show FUNCTION CALL STACK            │
│                                                                      │
│ How does the debugger know:                                        │
│   • Which address corresponds to line 42?                          │
│   • Where is my_variable stored?                                   │
│   • What are the function names in the call stack?                 │
│                                                                      │
│ Answer: DEBUG INFORMATION embedded in the executable               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### DWARF Debug Format

Most Unix-like systems use DWARF:

```
┌─────────────────────────────────────────────────────────────────────┐
│ DWARF DEBUG SECTIONS                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ .debug_info                                                         │
│ ─────────────────────────                                           │
│ Describes program structure:                                        │
│   • Functions: name, parameters, return type                       │
│   • Variables: name, type, location                                │
│   • Types: structs, enums, pointers                                │
│                                                                      │
│ .debug_line                                                         │
│ ─────────────────────────                                           │
│ Maps addresses to source locations:                                │
│   • Address 0x401000 → main.zig, line 5, column 1                  │
│   • Address 0x401010 → main.zig, line 6, column 5                  │
│   • ...                                                             │
│                                                                      │
│ .debug_abbrev                                                       │
│ ─────────────────────────                                           │
│ Abbreviation codes for compact encoding                            │
│                                                                      │
│ .debug_str                                                          │
│ ─────────────────────────                                           │
│ String table for names                                              │
│                                                                      │
│ The linker must:                                                    │
│   • Merge debug sections from all object files                     │
│   • Update addresses in debug info after relocation                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 10: The Complete Picture

### Full Compilation Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│ FROM SOURCE TO EXECUTABLE                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                      main.zig                                │  │
│   │                                                              │  │
│   │   const std = @import("std");                               │  │
│   │   pub fn main() void {                                      │  │
│   │       std.debug.print("Hello!\n", .{});                    │  │
│   │   }                                                          │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│   ─────────────────────────┼────────────────────────────────────── │
│   FRONTEND                 │                                        │
│   ─────────────────────────┼────────────────────────────────────── │
│                            ▼                                        │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐           │
│   │  Tokenizer  │ →  │   Parser    │ →  │   AstGen    │           │
│   │             │    │   (AST)     │    │   (ZIR)     │           │
│   └─────────────┘    └─────────────┘    └──────┬──────┘           │
│                                                 │                   │
│                                                 ▼                   │
│                                          ┌─────────────┐           │
│                                          │    Sema     │           │
│                                          │   (AIR)     │           │
│                                          └──────┬──────┘           │
│                                                 │                   │
│   ─────────────────────────────────────────────┼──────────────────  │
│   BACKEND                                       │                   │
│   ─────────────────────────────────────────────┼──────────────────  │
│                                                 ▼                   │
│                                          ┌─────────────┐           │
│                                          │   Codegen   │           │
│                                          │   (machine  │           │
│                                          │    code)    │           │
│                                          └──────┬──────┘           │
│                                                 │                   │
│   ─────────────────────────────────────────────┼──────────────────  │
│   LINKER                                        │                   │
│   ─────────────────────────────────────────────┼──────────────────  │
│                                                 ▼                   │
│   ┌───────────────────────────────────────────────────────────────┐│
│   │                         LINKER                                 ││
│   │                                                                ││
│   │  1. Collect object code                                       ││
│   │  2. Resolve symbols                                           ││
│   │  3. Merge sections                                            ││
│   │  4. Assign addresses                                          ││
│   │  5. Apply relocations                                         ││
│   │  6. Generate PLT/GOT (if dynamic)                             ││
│   │  7. Write executable                                          ││
│   └────────────────────────────┬──────────────────────────────────┘│
│                                │                                    │
│                                ▼                                    │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                       EXECUTABLE                             │  │
│   │                                                              │  │
│   │  $ ./main                                                   │  │
│   │  Hello!                                                      │  │
│   │                                                              │  │
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
│ 1. LINKING COMBINES PIECES                                          │
│    • Object files have holes (undefined references)                │
│    • Linker fills holes with actual addresses                      │
│    • Result is a complete, runnable program                        │
│                                                                      │
│ 2. SYMBOLS ARE NAMES                                                │
│    • Functions and variables have symbolic names                   │
│    • Linker matches "undefined" to "defined" symbols               │
│    • Unresolved symbols cause linker errors                        │
│                                                                      │
│ 3. RELOCATIONS FIX ADDRESSES                                        │
│    • Object files don't know final addresses                       │
│    • Relocations say "fill in address of X here"                   │
│    • Different types: absolute, PC-relative, GOT                   │
│                                                                      │
│ 4. STATIC vs DYNAMIC                                                │
│    • Static: copy library code into executable                     │
│    • Dynamic: reference library, load at runtime                   │
│    • GOT/PLT enable dynamic linking                                │
│                                                                      │
│ 5. MULTIPLE FORMATS                                                 │
│    • ELF (Linux), Mach-O (macOS), PE (Windows)                    │
│    • Different structures, same concepts                           │
│                                                                      │
│ 6. ZIG HAS ITS OWN LINKERS                                         │
│    • Enables cross-compilation                                     │
│    • Enables incremental linking                                   │
│    • No external dependencies                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Conclusion

The linker is the final piece of the compilation puzzle. It takes all the separate object files - each with their own code, data, and symbolic references - and weaves them together into a single executable.

Zig's custom linkers provide:
- **Cross-compilation** without external tools
- **Incremental linking** for fast development cycles
- **Reproducible builds** with deterministic output
- **Full control** over the linking process

This completes our journey through the Zig compiler! From tokenization through parsing, AST generation, semantic analysis, code generation, and finally linking - we've seen how source code becomes an executable program.

---

**Previous**: [Part 6: AIR and Code Generation](./06-air-codegen.md)

**Series Index**:
1. [Bootstrap Process](./01-bootstrap-process.md)
2. [Tokenizer](./02-tokenizer.md)
3. [Parser and AST](./03-parser-ast.md)
4. [ZIR Generation](./04-zir-generation.md)
5. [Semantic Analysis](./05-sema.md)
6. [AIR and Code Generation](./06-air-codegen.md)
7. **Linking** (this article)

---

## Further Reading

- [Linkers and Loaders](https://www.iecc.com/linker/) by John R. Levine
- [ELF Specification](https://refspecs.linuxfoundation.org/elf/elf.pdf)
- [Mach-O File Format](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/MachOTopics/)
- [PE/COFF Specification](https://docs.microsoft.com/en-us/windows/win32/debug/pe-format)
- [How the Zig Linker Works](https://andrewkelley.me) (Andrew Kelley's blog)
