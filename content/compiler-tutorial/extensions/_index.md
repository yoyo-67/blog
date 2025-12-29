---
title: "Extensions"
weight: 7
---

# Compiler Extensions

Now that you have a working compiler, let's extend it with real-world features that production compilers need.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         EXTENSION TOPICS                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────┐                                   │
│   │  COMPILATION UNITS & NAMESPACES     │                                   │
│   │  Split code across multiple files   │                                   │
│   │  Import and reuse modules           │                                   │
│   └─────────────────────────────────────┘                                   │
│                                                                              │
│   ┌─────────────────────────────────────┐                                   │
│   │  INCREMENTAL COMPILATION            │                                   │
│   │  Cache compilation results          │                                   │
│   │  Only rebuild what changed          │                                   │
│   └─────────────────────────────────────┘                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What You'll Learn

| Section | Topic | What You'll Build |
|---------|-------|-------------------|
| [1. Compilation Units](01-compilation-units/) | Multi-file projects | Import system, namespaces, dot notation |
| [2. Incremental Compilation](02-incremental-compilation/) | Build caching | File cache, function cache, smart rebuilds |

---

## Prerequisites

Complete the core compiler tutorial first:
- Lexer, Parser, ZIR, Sema, Codegen

These extensions build on top of your working compiler.

---

## Start Here

Begin with [Compilation Units & Namespaces](01-compilation-units/) →
