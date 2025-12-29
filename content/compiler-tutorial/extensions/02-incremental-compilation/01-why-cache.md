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

## What We'll Cache

### Level 1: File-Level Cache (ZirCache)

```
Cache key: combined_hash (includes file + ALL transitive imports)
Cache value: complete LLVM IR for this file

If the combined hash matches, skip all compilation.
```

### Level 2: Function-Level Cache (AirCache)

```
Cache key: file:function_name → ZIR hash
Cache value: LLVM IR for just that function

Even if a file changed, unchanged functions use cached output.
```

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
│   ├── Check modification time (mtime) - fast first check                     │
│   └── If mtime differs, hash content to confirm                              │
│                                                                              │
│   Transitive dependencies changed?                                           │
│   ├── main.mini imports math.mini                                            │
│   ├── math.mini imports utils.mini                                           │
│   ├── utils.mini changes                                                     │
│   └── BOTH main.mini AND math.mini need recompilation!                       │
│                                                                              │
│   Function changed?                                                          │
│   ├── Hash the function's ZIR instructions                                   │
│   └── If hash differs, recompile just that function                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Combined Hash Concept

A file's "combined hash" includes ALL of its dependencies:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         COMBINED HASH                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   main.mini imports: math.mini                                               │
│   math.mini imports: utils.mini                                              │
│                                                                              │
│   combined_hash(main.mini) = hash(                                           │
│       main.mini content +                                                    │
│       math.mini content +                                                    │
│       utils.mini content                                                     │
│   )                                                                          │
│                                                                              │
│   If ANY file in the chain changes, combined_hash changes.                   │
│   This ensures we never use stale cache entries.                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What We'll Build

A cache with:

1. **FileHashCache** - Track mtime, content hash, and imports per file
2. **Combined hash** - Include ALL transitive dependencies in the key
3. **ZirCache** - File-level LLVM IR cache with Git-style storage
4. **AirCache** - Function-level LLVM IR cache
5. **Surgical patching** - Replace only changed sections
6. **Disk persistence** - Binary format for speed

---

## Verify Your Understanding

### Question 1
```
Files: main.mini, math.mini, utils.mini
main.mini imports math.mini
math.mini imports utils.mini
You modify utils.mini

Which files need recompilation?
Answer: ALL THREE! Because combined hash includes transitive deps.
```

### Question 2
```
math.mini has functions: add, sub, mul
You change the implementation of mul

With per-function caching, how many functions are recompiled?
Answer: Just 1 (mul). add and sub use cached output.
```

### Question 3
```
main.mini imports math.mini
You add a comment to math.mini (whitespace only)

Does main.mini's combined hash change?
Answer: Yes! Content hash changed, so combined hash changed.
(This is a trade-off: simpler logic, occasional false positives)
```

---

## What's Next

Let's start by building change detection with FileHashCache.

Next: [Lesson 2.2: Change Detection](../02-file-hashing/) →
