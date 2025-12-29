---
title: "Section 2: Incremental Compilation"
weight: 2
---

# Section 2: Incremental Compilation

Compiling from scratch every time is slow. This section teaches you how to cache results and only recompile what changed.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         INCREMENTAL COMPILATION                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   First build:                          Second build (only main.mini changed)│
│   ─────────────                         ─────────────────────────────────────│
│                                                                              │
│   main.mini ──► compile ──┐             main.mini ──► compile ──┐            │
│   math.mini ──► compile ──┼──► output   math.mini ──► [CACHED]──┼──► output  │
│   utils.mini ─► compile ──┘             utils.mini ─► [CACHED]──┘            │
│                                                                              │
│   Time: 3 units                         Time: 1 unit (3x faster!)            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What You'll Build

A multi-level caching system that:
- Detects when source files change (via timestamps and hashes)
- Caches LLVM IR at the file level
- Caches LLVM IR at the function level (even finer-grained!)
- Tracks dependencies between files
- Invalidates cache when dependencies change

---

## Cache Levels

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         CACHE LEVELS                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Level 1: FILE CACHE                                                        │
│   ─────────────────                                                          │
│   "Has main.mini changed since last compile?"                                │
│   Key: file path                                                             │
│   Value: mtime, hash, compiled LLVM IR                                       │
│                                                                              │
│   Level 2: FUNCTION CACHE (AIR Cache)                                        │
│   ─────────────────────────────────                                          │
│   "Has the add() function changed?"                                          │
│   Key: file:function_name                                                    │
│   Value: ZIR hash, compiled LLVM IR for that function                        │
│                                                                              │
│   Even if a file changes, unchanged functions can use cached output.         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Lessons

| Lesson | Topic | What You'll Build |
|--------|-------|-------------------|
| [1. Why Cache?](01-why-cache/) | Motivation | Understanding the problem |
| [2. File Hashing](02-file-hashing/) | Change detection | Hash functions, mtime checks |
| [3. File Cache](03-file-cache/) | File-level caching | Cache structure, save/load |
| [4. Function Cache](04-function-cache/) | Per-function caching | ZIR hashing, AIR cache |
| [5. Multi-Level Cache](05-multi-level-cache/) | Complete system | Putting it all together |

---

## Real-World Impact

Production compilers spend significant effort on incremental compilation:

- **Rust**: Incremental compilation saves ~50% build time
- **Go**: Fast compilation is a core design goal
- **TypeScript**: `--incremental` flag for caching

Even our simple cache can show dramatic improvements on larger projects.

---

## Start Here

Begin with [Lesson 2.1: Why Cache?](01-why-cache/) →
