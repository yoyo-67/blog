---
title: "Section 1: Compilation Units & Imports"
weight: 1
---

# Section 1: Compilation Units & Imports

Real programs aren't written in a single file. This section teaches you how to split code across multiple files and import them, **step by step**.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         WHAT YOU'LL BUILD                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   math.mini                             main.mini                            │
│   ┌────────────────────┐               ┌────────────────────────────┐       │
│   │ fn add(a, b) {     │               │ import "math.mini" as math;│       │
│   │   return a + b;    │◄──────────────│                            │       │
│   │ }                  │   imports     │ fn main() {                │       │
│   │                    │               │   return math.add(1, 2);   │       │
│   │ fn square(n) {     │               │ }                          │       │
│   │   return n * n;    │               └────────────────────────────┘       │
│   │ }                  │                                                     │
│   └────────────────────┘                                                     │
│                                                                              │
│   Result: Both files compiled together, functions accessible via namespace   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## How This Tutorial Works

Each module presents **3-4 sub-lessons** that follow this pattern:

1. **The Problem** - What specific issue are we solving?
2. **The Solution** - Pseudocode you can translate to any language
3. **Try It Yourself** - Steps to verify your implementation works
4. **What This Enables** - What you can do now that you couldn't before

---

## The 5 Modules

| Module | What You'll Build | Sub-lessons |
|--------|-------------------|-------------|
| [1. Compilation Units](01-what-is-a-unit/) | Data structure for source files | 3 |
| [2. Import Parsing](02-imports/) | Parse `import "file" as name;` syntax | 4 |
| [3. Loading Imports](03-loading-imports/) | Recursive file loading | 4 |
| [4. Namespace Prefixing](04-namespace-prefixing/) | Prevent name collisions | 3 |
| [5. Dot Notation](05-dot-notation/) | `math.add()` syntax sugar | 4 |

**Total: 18 sub-lessons** taking you from single-file to multi-file compilation.

---

## Module Summaries

### Module 1: Compilation Units
**Problem:** Your compiler only handles one source file.

You'll build a `CompilationUnit` struct that:
- Wraps a source file (path, source, AST)
- Tracks what other files it imports
- Links to imported compilation units

### Module 2: Import Parsing
**Problem:** How do we express "I need code from another file"?

You'll implement:
- New lexer tokens: `import`, `as`, string literals
- AST node for import declarations
- Parser function for `import "path" as namespace;`
- Automatic namespace derivation from filename

### Module 3: Loading Imports
**Problem:** Parsing imports doesn't load the files.

You'll implement:
- `extractImports()` - Find imports in parsed AST
- `resolvePath()` - Handle relative file paths
- `loadImports()` - Recursive loading with cycle detection
- `units_map` - Prevent loading the same file twice

### Module 4: Namespace Prefixing
**Problem:** Two files might have functions with the same name.

You'll implement:
- `generateProgram()` - Collect all functions
- Namespace prefix: `add` from `math` becomes `math_add`
- Multi-level prefixes for nested imports

### Module 5: Dot Notation
**Problem:** Writing `math_add(1, 2)` is ugly.

You'll implement:
- Dot token recognition
- `math.add(1, 2)` → `math_add(1, 2)` transformation
- Clean calling syntax for imported functions

---

## End Result

By the end, your compiler will transform:

```
// main.mini
import "math.mini" as math;

fn main() i32 {
    return math.add(10, 5);
}

// math.mini
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

Into a program where:
1. `math.mini` is automatically loaded and parsed
2. Its `add` function becomes `math_add` (no collisions)
3. The call `math.add(10, 5)` becomes `math_add(10, 5)`
4. Both files are compiled together into one output

---

## Prerequisites

Before starting, you should have:
- A working compiler that handles single files
- Lexer with identifier, keyword, and basic token support
- Parser that produces an AST
- Code generator that emits output

---

## Start Here

**[→ Module 1: What is a Compilation Unit?](01-what-is-a-unit/)** - The foundation for multi-file support
