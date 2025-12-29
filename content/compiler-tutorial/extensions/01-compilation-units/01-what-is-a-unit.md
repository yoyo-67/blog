---
title: "1.1: What is a Compilation Unit?"
weight: 1
---

# Lesson 1.1: What is a Compilation Unit?

Before we can import files, we need to represent each source file as a **compilation unit**.

---

## Goal

Define a data structure that represents a single source file and its relationship to other files.

---

## What is a Compilation Unit?

A compilation unit wraps everything about a single source file:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         COMPILATION UNIT                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CompilationUnit {                                                          │
│       path:    "math_utils.mini"           // Where the file lives          │
│       source:  "fn add(a, b) { ... }"      // The raw source code           │
│       tree:    AST                          // Parsed syntax tree            │
│       imports: { "math" → Import }          // Files this unit imports       │
│   }                                                                          │
│                                                                              │
│   Import {                                                                   │
│       path:      "math.mini"               // Path to imported file          │
│       namespace: "math"                     // How we refer to it            │
│       unit:      *CompilationUnit          // Pointer to loaded unit         │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Compilation Units?

Previously, our compiler worked like this:

```
source string → lexer → parser → AST → codegen → output
```

With multiple files, we need:

```
main.mini ─────────────────────────┐
                                   ▼
                            ┌─────────────┐
math.mini ────────────────► │  Compiler   │ ───► output
                            └─────────────┘
                                   ▲
utils.mini ────────────────────────┘
```

The CompilationUnit tracks which files we've loaded and how they relate.

---

## Data Structures

### CompilationUnit

```
CompilationUnit = struct {
    path:      string,                    // File path
    source:    string,                    // Source code content
    tree:      AST,                       // Parsed AST
    imports:   Map<string, Import>,       // namespace → Import
    allocator: Allocator,                 // Memory allocator
}
```

### Import

```
Import = struct {
    path:      string,                    // "math_utils.mini"
    namespace: string,                    // "math"
    unit:      *CompilationUnit | null,   // Pointer to loaded unit (null initially)
}
```

---

## Implementation Steps

1. **Create CompilationUnit struct** with fields: path, source, tree, imports

2. **Create Import struct** with fields: path, namespace, unit

3. **Add init function**:
```
CompilationUnit.init(allocator, path) -> CompilationUnit {
    return CompilationUnit {
        path: path,
        source: "",
        tree: undefined,
        imports: empty_map,
        allocator: allocator,
    }
}
```

4. **Add load function** (we'll implement fully in the next lesson):
```
CompilationUnit.load(arena) {
    // Read file from disk
    self.source = read_file(self.path)

    // Parse into AST
    self.tree = parse(self.source)

    // Extract imports (next lesson)
    self.extractImports()
}
```

---

## Verify Your Implementation

### Test 1: Create a compilation unit
```
Input:  unit = CompilationUnit.init(allocator, "test.mini")
Check:  unit.path == "test.mini"
        unit.source == ""
        unit.imports.count() == 0
```

### Test 2: Import structure
```
Input:  import = Import { path: "math.mini", namespace: "math", unit: null }
Check:  import.path == "math.mini"
        import.namespace == "math"
        import.unit == null
```

---

## What's Next

Now that we have the data structure, let's parse import statements.

Next: [Lesson 1.2: Import Statements](../02-imports/) →
