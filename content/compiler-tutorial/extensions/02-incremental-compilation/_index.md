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

A multi-level caching system with four components:

1. **FileHashCache** - Track file changes via mtime, content hash, and imports
2. **ZirCache** - Cache LLVM IR at the file level using Git-style storage
3. **AirCache** - Cache LLVM IR at the function level for fine-grained reuse
4. **Surgical Patching** - Partially rebuild files using embedded markers

---

## Cache Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         CACHE LEVELS                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   FileHashCache (Change Detection)                                           │
│   ────────────────────────────────                                           │
│   "Has main.mini or ANY of its imports changed?"                             │
│   Key: file path                                                             │
│   Value: mtime, hash, imports list                                           │
│                                                                              │
│   ZirCache (File-Level Cache)                                                │
│   ───────────────────────────                                                │
│   "Do we have cached LLVM IR for this file+dependencies combo?"              │
│   Key: combined hash (file + all transitive imports)                         │
│   Value: LLVM IR stored in Git-style objects                                 │
│                                                                              │
│   AirCache (Function-Level Cache)                                            │
│   ───────────────────────────────                                            │
│   "Has this specific function changed?"                                      │
│   Key: file:function_name → ZIR hash                                         │
│   Value: LLVM IR for just this function                                      │
│                                                                              │
│   Surgical Patching                                                          │
│   ─────────────────                                                          │
│   "Can we patch just the changed sections?"                                  │
│   Uses file markers: ; ==== FILE: path:hash ====                             │
│   Reassembles output from cached + recompiled sections                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Cache Directory Structure

```
.mini_cache/
├── file_hashes.bin      # FileHashCache index (binary for speed)
├── zir_index.bin        # ZirCache path→hash index
├── zir/                 # Git-style file-level cache
│   └── 3d/
│       └── b3b7314a73226b
├── objects/             # Git-style function-level cache
│   ├── 9a/
│   │   └── 2eb98b6d927e93
│   └── df/
│       └── 15672fe8b1d382
└── combined/            # Full IRs with markers for surgical patching
    └── main.mini.ll
```

---

## Lessons

| Lesson | Topic | What You'll Build |
|--------|-------|-------------------|
| [1. Why Cache?](01-why-cache/) | Motivation | Understanding the problem |
| [2. Change Detection](02-file-hashing/) | FileHashCache | Mtime, hashing, import tracking |
| [3. File Cache](03-file-cache/) | ZirCache | Git-style file-level cache |
| [4. Function Cache](04-function-cache/) | AirCache | Per-function caching with ZIR hashing |
| [5. Surgical Patching](05-surgical-patching/) | Partial rebuilds | File markers, incremental reassembly |
| [6. Multi-Level Cache](06-multi-level-cache/) | Complete system | Putting it all together |

---

## Real-World Impact

Production compilers spend significant effort on incremental compilation:

- **Rust**: Incremental compilation saves ~50% build time
- **Go**: Fast compilation is a core design goal
- **TypeScript**: `--incremental` flag for caching

Even our multi-level cache can show dramatic improvements on larger projects.

---

## Start Here

Begin with [Lesson 2.1: Why Cache?](01-why-cache/) →
