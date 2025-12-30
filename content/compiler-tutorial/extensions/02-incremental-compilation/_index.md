---
title: "Section 2: Incremental Compilation"
weight: 2
---

# Section 2: Incremental Compilation

Compiling from scratch every time is slow. This section teaches you how to cache results and only recompile what changed.

---

## Real Benchmark: 10,000 Files

| Scenario | Time | Speedup |
|----------|------|---------|
| Cold build (clean cache) | **7.97s** | baseline |
| Warm build (no changes) | **1.25s** | 6.4x faster |
| 1 file changed | **1.81s** | 4.4x faster |

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    MEASURED TIMING BREAKDOWN                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   INCREMENTAL BUILD (1 file changed, 1.81s total):                           │
│                                                                              │
│   [time] Cache load: 393ms, Hash compute: 938ms                              │
│   [incremental] Surgical patch: 1/10001 files changed                        │
│   [time] Compile: 335ms, Save: 142ms                                         │
│                                                                              │
│   Key insight: Hash compute (0.9s) dominates, not compilation!               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Start Here: The Big Picture

**[→ Overview: What Actually Matters](00-overview/)**

Before diving into implementation, read the overview to understand:
- Where time is actually spent
- Which optimizations are **critical** vs **nice-to-have**
- The complete build flow

---

## What You'll Build

A multi-level caching system with four components:

| Component | Purpose | Priority |
|-----------|---------|----------|
| **FileHashCache** | Track changes via mtime + hash + imports | Critical |
| **ZirCache** | File-level LLVM IR cache | Critical |
| **Surgical Patching** | Partial output rebuilds | Critical |
| **AirCache** | Function-level LLVM IR cache | Nice to have |

---

## Lessons

| Lesson | Topic | Priority |
|--------|-------|----------|
| [0. Overview](00-overview/) | Big picture, benchmarks | **Read first** |
| [1. Why Cache?](01-why-cache/) | Motivation | Understand |
| [2. Change Detection](02-file-hashing/) | FileHashCache | **Critical** |
| [3. File Cache](03-file-cache/) | ZirCache | **Critical** |
| [4. Function Cache](04-function-cache/) | AirCache | Nice to have |
| [5. Surgical Patching](05-surgical-patching/) | Partial rebuilds | **Critical** |
| [6. Multi-Level Cache](06-multi-level-cache/) | Complete system | Integration |

---

## Key Insight

With 10,000 files, the **minimum time is ~1.2 seconds** regardless of what changed:
- Cache load: **390ms** (loading file_hashes.bin)
- Hash compute: **847ms** (mtime checks + dependency traversal for 10k files)

The actual compilation is fast:
- Compiling 1 changed file: **335ms** (including surgical patching)
- Compiling all 10k files: **4700ms** (cold build only)

**This means:** The bottleneck is hash computation, not compilation. Mtime-first checking, stack-allocated buffers, and binary cache format are critical.

---

## Cache Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         OPTIMIZATION PRIORITIES                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CRITICAL (must have):                                                      │
│   ─────────────────────                                                      │
│   • Mtime-first checking     → Avoid reading unchanged files                 │
│   • Binary cache format      → 10x faster than JSON                          │
│   • Combined hash            → One check includes all dependencies           │
│   • Surgical patching        → Recompile only changed sections               │
│                                                                              │
│   NICE TO HAVE:                                                              │
│   ─────────────                                                              │
│   • Per-function caching     → Only helps within changed files               │
│   • Git-style storage        → Matters at 100k+ cached objects               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Start Here

**[→ Overview: What Actually Matters](00-overview/)** - Benchmarks and big picture

Or jump to implementation: [Lesson 2.1: Why Cache?](01-why-cache/) →
