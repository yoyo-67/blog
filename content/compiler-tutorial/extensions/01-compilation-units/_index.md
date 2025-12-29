---
title: "Section 1: Compilation Units & Namespaces"
weight: 1
---

# Section 1: Compilation Units & Namespaces

Real programs aren't written in a single file. This section teaches you how to split code across multiple files and import them.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         MULTI-FILE COMPILATION                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   math_utils.mini                        main.mini                           │
│   ┌────────────────────┐                ┌────────────────────────────┐      │
│   │ fn add(a, b) {     │                │ import "math_utils.mini"   │      │
│   │   return a + b;    │◄───────────────│        as math;            │      │
│   │ }                  │   imports      │                            │      │
│   │                    │                │ fn main() {                │      │
│   │ fn square(n) {     │                │   return math.add(1, 2);   │      │
│   │   return n * n;    │                │ }                          │      │
│   │ }                  │                └────────────────────────────┘      │
│   └────────────────────┘                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What You'll Build

An import system that:
- Parses `import "file.mini" as namespace;` statements
- Loads and compiles imported files
- Prefixes imported functions with their namespace
- Supports `namespace.function()` syntax for calling imported functions

---

## Lessons

| Lesson | Topic | What You'll Add |
|--------|-------|-----------------|
| [1. What is a Compilation Unit?](01-what-is-a-unit/) | Core concept | CompilationUnit data structure |
| [2. Import Statements](02-imports/) | Parsing imports | Lexer tokens, parser rules |
| [3. Loading Imports](03-loading-imports/) | File loading | Recursive import resolution |
| [4. Namespace Prefixing](04-namespace-prefixing/) | Name mangling | Function renaming in codegen |
| [5. Dot Notation](05-dot-notation/) | Syntax sugar | `math.add()` instead of `math_add()` |

---

## The Big Picture

By the end, your compiler will transform:

```
// main.mini
import "math.mini" as math;

fn main() i32 {
    return math.add(10, 5);
}
```

Into a program where:
1. `math.mini` is loaded and parsed
2. Its `add` function becomes `math_add`
3. The call `math.add(10, 5)` becomes `math_add(10, 5)`
4. Both are compiled together into one output

---

## Start Here

Begin with [Lesson 1: What is a Compilation Unit?](01-what-is-a-unit/) →
