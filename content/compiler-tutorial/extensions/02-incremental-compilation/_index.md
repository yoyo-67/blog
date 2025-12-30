---
title: "Section 2: Incremental Compilation"
weight: 2
---

# Section 2: Incremental Compilation

Compiling from scratch every time is slow. This section teaches you how to build an incremental compilation system **step by step**, with each lesson presenting a problem and its solution.

---

## Real Benchmark: 10,000 Files

| Scenario | Time | Speedup |
|----------|------|---------|
| Cold build (clean cache) | **7.97s** | baseline |
| Warm build (no changes) | **1.25s** | 6.4x faster |
| 1 file changed | **1.81s** | 4.4x faster |

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    WHAT YOU'LL ACHIEVE                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Before: Change 1 file → Recompile 10,000 files → 8 seconds                 │
│   After:  Change 1 file → Recompile 1 file      → 0.3 seconds               │
│                                                                              │
│   Speedup: 26x faster for incremental builds                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## How This Tutorial Works

Each module is **standalone** and teaches one caching component. Each module contains **3-5 sub-lessons** that follow this pattern:

1. **The Problem** - What specific issue are we solving?
2. **The Solution** - Pseudocode you can translate to any language
3. **Try It Yourself** - Steps to verify your implementation works
4. **Benchmark Data** - Real numbers so you know what to expect

---

## The 6 Modules

| Module | What You'll Build | Sub-lessons |
|--------|-------------------|-------------|
| [0. Overview](00-overview/) | Understanding the big picture | - |
| [1. File Change Detection](01-file-change-detection/) | Know when files change | 5 |
| [2. File-Level Cache](02-file-cache/) | Cache compiled output per file | 4 |
| [3. Function-Level Cache](03-function-cache/) | Cache compiled output per function | 4 |
| [4. Multi-Level Integration](04-multi-level-cache/) | Combine all caches | 3 |
| [5. Surgical Patching](05-surgical-patching/) | Recompile only changed files | 5 |
| [6. Performance](06-performance/) | Optimize for 10K+ files | 3 |

**Total: 24 sub-lessons** taking you from zero to a production-ready incremental compiler.

---

## Module Summaries

### Module 1: File Change Detection
**Problem:** How do we know if a file needs recompilation?

You'll build a `FileHashCache` that:
- Uses mtime to skip unchanged files (10x faster than reading)
- Tracks content hashes for reliable change detection
- Extracts imports to track dependencies
- Persists to disk in fast binary format

### Module 2: File-Level Cache
**Problem:** How do we store and retrieve compiled output?

You'll build a `ZirCache` that:
- Stores IR (Intermediate Representation) per file
- Uses Git-style content addressing (deduplication)
- Maintains a fast in-memory index
- Persists efficiently across builds

### Module 3: Function-Level Cache
**Problem:** If only 1 function changed, why recompile all 10?

You'll build an `AirCache` that:
- Identifies functions uniquely
- Hashes function content (name, params, body)
- Caches individual function output
- Integrates with code generation

### Module 4: Multi-Level Integration
**Problem:** How do these caches work together?

You'll build a `MultiLevelCache` that:
- Combines all three caches
- Implements the "fast path" (nothing changed)
- Loads/saves all caches atomically

### Module 5: Surgical Patching
**Problem:** When 1 file changes, how do we avoid rebuilding everything?

You'll implement:
- File markers in output (`; ==== FILE: path:hash ====`)
- Parsing cached sections
- Detecting which files changed
- Reassembling output with minimal recompilation

### Module 6: Performance
**Problem:** How do we make this fast for 10,000+ files?

You'll learn:
- Avoiding redundant dependency visits
- Minimizing memory allocations
- Measuring to find bottlenecks

---

## Key Techniques (Ranked by Impact)

| Technique | Savings | Module |
|-----------|---------|--------|
| mtime checking | 10x faster change detection | 1 |
| Binary format | 20x faster cache load | 1, 2 |
| Combined hash fast path | 166x faster "nothing changed" | 4 |
| Surgical patching | 100x faster "1 file changed" | 5 |
| Allocation optimization | 5x faster traversal | 6 |

---

## Prerequisites

Before starting, you should have:
- A working compiler that can compile source → IR
- Basic understanding of hash functions
- Familiarity with file I/O in your language

---

## Start Here

**[→ Overview: What Actually Matters](00-overview/)** - Benchmarks and architecture

Then: **[Module 1: File Change Detection](01-file-change-detection/)** - Your first cache
