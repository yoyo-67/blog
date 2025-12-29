---
title: "2.1: Why Cache?"
weight: 1
---

# Lesson 2.1: Why Cache?

Before building a cache, let's understand why we need one.

---

## Goal

Understand the problem of slow recompilation and how caching solves it.

---

## The Problem

Every time you run the compiler, it does everything from scratch:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         FULL RECOMPILATION                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   You change ONE line in main.mini...                                        │
│                                                                              │
│   main.mini ──► lex ──► parse ──► ZIR ──► sema ──► codegen ──┐              │
│   math.mini ──► lex ──► parse ──► ZIR ──► sema ──► codegen ──┼──► output    │
│   utils.mini ─► lex ──► parse ──► ZIR ──► sema ──► codegen ──┘              │
│                                                                              │
│   ALL files recompiled, even though only main.mini changed!                  │
│                                                                              │
│   With 100 files, this wastes 99% of the work.                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Solution: Cache Results

Store compilation results and reuse them when nothing changed:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         WITH CACHING                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   main.mini changed?  YES ──► recompile ────────────────────┐               │
│   math.mini changed?  NO  ──► use cached LLVM IR ───────────┼──► output     │
│   utils.mini changed? NO  ──► use cached LLVM IR ───────────┘               │
│                                                                              │
│   Only 1 file recompiled instead of 3!                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What We Can Cache

### Level 1: Whole File Output

```
Cache entry:
    path: "math.mini"
    last_modified: 1703789456
    content_hash: 0x8a3f2b1c...
    llvm_ir: "define i32 @math_add..."
```

If the file hasn't changed, skip everything and use cached LLVM IR.

### Level 2: Per-Function Output

```
Cache entry:
    file: "math.mini"
    function: "add"
    zir_hash: 0x5c7d9e2a...
    llvm_ir: "define i32 @math_add..."
```

Even if a file changed, unchanged functions can use cached output.

Example:
- `math.mini` has functions `add`, `sub`, `mul`
- You only modify `mul`
- `add` and `sub` use cached LLVM IR
- Only `mul` is recompiled

---

## Cache Invalidation

The hard part: knowing WHEN to invalidate the cache.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         INVALIDATION RULES                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   File changed?                                                              │
│   ├── Check modification time (mtime)                                        │
│   └── Check content hash (for moved/touched files)                           │
│                                                                              │
│   Dependency changed?                                                        │
│   ├── main.mini imports math.mini                                            │
│   ├── math.mini changes                                                      │
│   └── main.mini MIGHT need recompilation (its calls might break)            │
│                                                                              │
│   Function changed?                                                          │
│   ├── Hash the function's ZIR instructions                                   │
│   └── If hash differs, recompile just that function                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What We'll Build

A cache with:

1. **File mtime tracking** - Quick "did file change?" check
2. **Content hashing** - Reliable change detection
3. **Dependency tracking** - Know what depends on what
4. **Per-function hashing** - Fine-grained invalidation
5. **Disk persistence** - Cache survives between runs

---

## Verify Your Understanding

### Question 1
```
Files: main.mini, math.mini, utils.mini
main.mini imports math.mini
You modify utils.mini

Which files need recompilation?
Answer: Only utils.mini (main.mini doesn't depend on it)
```

### Question 2
```
math.mini has functions: add, sub, mul
You change the implementation of mul

With per-function caching, how many functions are recompiled?
Answer: Just 1 (mul). add and sub use cached output.
```

---

## What's Next

Let's start by detecting when files change.

Next: [Lesson 2.2: File Hashing](../02-file-hashing/) →
