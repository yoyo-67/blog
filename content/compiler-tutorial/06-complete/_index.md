---
title: "Section 6: Complete"
weight: 6
---

# Section 6: Complete Compiler

Wire everything together into a working compiler.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        THE COMPLETE PIPELINE                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source Code                                                                │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────┐                                                               │
│   │  LEXER  │  → Tokens                                                     │
│   └────┬────┘                                                               │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────┐                                                               │
│   │ PARSER  │  → AST                                                        │
│   └────┬────┘                                                               │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────┐                                                               │
│   │   ZIR   │  → Untyped IR                                                 │
│   └────┬────┘                                                               │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────┐                                                               │
│   │  SEMA   │  → Typed IR (AIR) + Errors                                   │
│   └────┬────┘                                                               │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────┐                                                               │
│   │ CODEGEN │  → C Code                                                     │
│   └────┬────┘                                                               │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────┐                                                               │
│   │   CC    │  → Executable                                                 │
│   └─────────┘                                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What You've Built

A complete compiler in ~1000 lines that:
- Lexes source code into tokens
- Parses tokens into an AST
- Generates untyped IR (ZIR)
- Performs semantic analysis (Sema) producing typed IR (AIR)
- Generates C code
- Compiles to native executables

---

## Lessons in This Section

| Lesson | Topic | What You'll Do |
|--------|-------|----------------|
| [1. Integration](01-integration/) | Wire stages | Connect all components |
| [2. Walkthrough](02-walkthrough/) | Example | Trace a program through |
| [3. Test Suite](03-test-suite/) | Testing | Comprehensive tests |
| [4. Extensions](04-extensions/) | Next steps | Ideas for expanding |

---

## Lines of Code

Approximate counts by stage:

```
Lexer:      ~100-150 lines
Parser:     ~150-200 lines
ZIR Gen:    ~80-120 lines
Sema:       ~150-200 lines
Codegen:    ~100-150 lines
─────────────────────────
Total:      ~600-800 lines
```

Plus tests and utilities, easily under 1000 lines.

---

## What You Can Compile

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn main() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    const sum: i32 = x + y;
    return sum;
}
```

---

## Start Here

Begin with [Lesson 1: Integration](01-integration/) →
