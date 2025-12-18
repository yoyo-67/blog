---
title: "Section 5b: LLVM Backend"
weight: 7
---

# Section 5b: LLVM Code Generation

An alternative backend that generates LLVM IR instead of C.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        LLVM BACKEND PIPELINE                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR (Typed IR)                                                             │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────┐                                                       │
│   │  LLVM Codegen   │  Generate LLVM IR                                     │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │   output.ll     │  LLVM IR text format                                  │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ├──────────────────────┐                                         │
│            ▼                      ▼                                         │
│   ┌─────────────────┐    ┌─────────────────┐                                │
│   │      lli        │    │      llc        │                                │
│   │  (interpreter)  │    │   (compiler)    │                                │
│   └─────────────────┘    └────────┬────────┘                                │
│                                   │                                         │
│                                   ▼                                         │
│                          ┌─────────────────┐                                │
│                          │   executable    │                                │
│                          └─────────────────┘                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why LLVM?

LLVM provides:
- **Industrial-strength optimization** - Decades of optimization passes
- **Multiple targets** - x86, ARM, RISC-V, WebAssembly from one IR
- **Debugging support** - DWARF debug info generation
- **Ecosystem** - Clang, Rust, Swift all use LLVM

---

## Lessons in This Section

| Lesson | Topic | What You'll Learn |
|--------|-------|-------------------|
| [1. Introduction](01-intro-llvm/) | What is LLVM? | Overview and architecture |
| [2. IR Basics](02-llvm-ir-basics/) | LLVM IR | Modules, functions, instructions |
| [3. Types](03-type-mapping/) | Type mapping | Our types → LLVM types |
| [4. Functions](04-gen-functions/) | Generate functions | LLVM function definitions |
| [5. Instructions](05-gen-instructions/) | Generate code | Constants, arithmetic, returns |
| [6. Build & Run](06-building-running/) | Execute | Using lli and llc |

---

## Prerequisites

Complete the main tutorial through Section 4 (Sema) first. This section provides an alternative to Section 5 (C Codegen).

---

## Start Here

Begin with [Lesson 1: Introduction to LLVM](01-intro-llvm/) →
