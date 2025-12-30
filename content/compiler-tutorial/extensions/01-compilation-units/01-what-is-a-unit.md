---
title: "Module 1: What is a Compilation Unit?"
weight: 1
---

# Module 1: What is a Compilation Unit?

Before we can import files, we need to represent each source file as a **compilation unit**. This module teaches you to build the data structures that make multi-file compilation possible.

**What you'll build:**
- `CompilationUnit` struct to wrap source files
- `Import` struct to track dependencies
- `load()` method to read and parse files

---

## Sub-lesson 1.1: From Single File to Multi-File

### The Problem

Your compiler currently works like a pipeline for a single file:

```
source string → lexer → parser → AST → codegen → output
```

This breaks down when you have multiple files:

```
main.mini wants to use functions from math.mini
                    │
                    ▼
          How do we represent this?
          Where do we store math.mini's AST?
          How do we link them together?
```

We need a way to:
1. Represent each source file with its metadata
2. Track which files depend on which
3. Store multiple parsed ASTs

### The Solution

Create a `CompilationUnit` struct that wraps everything about a single source file.

**Data Structure:**

```
CompilationUnit {
    path: string              // "math.mini" or "lib/utils.mini"
    source: string            // The raw source code
    tree: AST                 // The parsed syntax tree
    imports: Map<string, Import>  // namespace → Import info
    allocator: Allocator      // Memory allocator
}
```

**Why These Fields?**

```
┌─────────────────────────────────────────────────────────────────────┐
│ COMPILATION UNIT FIELDS                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ path:      Where to find the file on disk                           │
│            Used for: error messages, resolving relative imports     │
│                                                                     │
│ source:    The actual source code text                              │
│            Used for: lexing, error messages with line content       │
│                                                                     │
│ tree:      The parsed AST                                           │
│            Used for: semantic analysis, code generation             │
│                                                                     │
│ imports:   Map of namespace → Import                                │
│            Used for: loading dependencies, linking units            │
│            Key is namespace ("math"), value is Import struct        │
│                                                                     │
│ allocator: Memory allocator for this unit                           │
│            Used for: allocating strings, AST nodes, etc.            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
CompilationUnit.init(allocator, path) -> CompilationUnit {
    return CompilationUnit {
        path: path,
        source: "",           // Empty until load() is called
        tree: undefined,      // Not parsed yet
        imports: Map.init(allocator),
        allocator: allocator,
    }
}
```

### Try It Yourself

1. Create the `CompilationUnit` struct with all fields
2. Implement `init()` function
3. Test:

```
// Test: Create a compilation unit
unit = CompilationUnit.init(allocator, "test.mini")

assert unit.path == "test.mini"
assert unit.source == ""
assert unit.imports.count() == 0
```

### What This Enables

You can now create a compilation unit for any source file:

```
main_unit = CompilationUnit.init(allocator, "main.mini")
math_unit = CompilationUnit.init(allocator, "math.mini")
utils_unit = CompilationUnit.init(allocator, "lib/utils.mini")
```

Each unit is independent and can be loaded/parsed separately.

---

## Sub-lesson 1.2: Tracking Imports

### The Problem

A compilation unit needs to know what other files it depends on. When we parse:

```
import "math.mini" as math;
import "utils.mini" as u;
```

We need to store:
1. The file path to import (`"math.mini"`)
2. The namespace to use (`math`)
3. A link to the imported unit (once loaded)

### The Solution

Create an `Import` struct to hold all information about a single import.

**Data Structure:**

```
Import {
    path: string                    // "math.mini" or "lib/utils.mini"
    namespace: string               // "math" or "u"
    unit: *CompilationUnit | null   // Pointer to loaded unit
}
```

**Why a Pointer?**

```
┌─────────────────────────────────────────────────────────────────────┐
│ IMPORT LIFECYCLE                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ 1. Parse import statement:                                          │
│    import "math.mini" as math;                                      │
│                                                                     │
│ 2. Create Import struct:                                            │
│    Import {                                                         │
│        path: "math.mini",                                           │
│        namespace: "math",                                           │
│        unit: null           ← Not loaded yet!                       │
│    }                                                                │
│                                                                     │
│ 3. After loading math.mini:                                         │
│    Import {                                                         │
│        path: "math.mini",                                           │
│        namespace: "math",                                           │
│        unit: &math_unit     ← Now points to loaded unit             │
│    }                                                                │
│                                                                     │
│ The pointer starts null and gets filled in when we load the file.   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Storing Imports in CompilationUnit:**

The `imports` field is a Map from namespace to Import:

```
// main.mini has:
// import "math.mini" as math;
// import "utils.mini" as u;

main_unit.imports = {
    "math" → Import { path: "math.mini", namespace: "math", unit: null },
    "u"    → Import { path: "utils.mini", namespace: "u", unit: null },
}
```

We use namespace as the key because that's how we'll look up imports when resolving function calls like `math.add()`.

### Try It Yourself

1. Create the `Import` struct
2. Test creating imports:

```
// Test: Create an import
import = Import {
    path: "math.mini",
    namespace: "math",
    unit: null,
}

assert import.path == "math.mini"
assert import.namespace == "math"
assert import.unit == null

// Test: Add import to compilation unit
unit = CompilationUnit.init(allocator, "main.mini")
unit.imports.put("math", import)

assert unit.imports.count() == 1
assert unit.imports.get("math").path == "math.mini"
```

### What This Enables

You can now track dependencies between files:

```
// After parsing main.mini which imports math.mini and utils.mini:
main_unit.imports = {
    "math"  → Import { path: "math.mini", ... },
    "utils" → Import { path: "utils.mini", ... },
}

// Later, look up by namespace:
if main_unit.imports.get("math") -> import {
    // Found! Can access import.path, import.unit, etc.
}
```

---

## Sub-lesson 1.3: Loading Source Files

### The Problem

We have empty compilation units. Now we need to:
1. Read the source file from disk
2. Parse it into an AST
3. (Later) Extract imports from the AST

### The Solution

Add a `load()` method to `CompilationUnit` that reads and parses the file.

**Implementation:**

```
CompilationUnit.load(self, arena) {
    // Step 1: Read source file from disk
    self.source = read_file(self.path)

    // Step 2: Create lexer from source
    lexer = Lexer.init(self.source)

    // Step 3: Parse into AST
    parser = Parser.init(arena.allocator(), &lexer)
    self.tree = parser.parse()

    // Step 4: Extract imports (we'll implement this in Module 3)
    self.extractImports(arena.allocator())
}
```

**Reading the File:**

```
read_file(path) -> string {
    file = open(path, "r")
    if file.error() {
        panic("Cannot open file: {}", path)
    }

    content = file.read_all()
    file.close()

    return content
}
```

**Error Handling:**

What if the file doesn't exist? You have options:
1. **Panic/crash** - Simple, good for early development
2. **Return error** - Let caller handle it
3. **Return Result type** - Explicit error handling

For now, we'll panic on file not found. You can add proper error handling later.

### The Complete Load Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│ LOAD() FLOW                                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Input: unit.path = "math.mini"                                      │
│                                                                     │
│ 1. read_file("math.mini")                                           │
│    → "fn add(a: i32, b: i32) i32 { return a + b; }"                 │
│                                                                     │
│ 2. Lexer.init(source)                                               │
│    → [fn] [add] [(] [a] [:] [i32] ...                               │
│                                                                     │
│ 3. Parser.parse()                                                   │
│    → AST { Root { decls: [FnDecl { name: "add", ... }] } }          │
│                                                                     │
│ 4. extractImports()                                                 │
│    → (No imports in this file)                                      │
│                                                                     │
│ Output: unit.source and unit.tree are populated                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Implement `load()` method
2. Create a test file on disk
3. Test:

```
// Create test file: test.mini
// Content: fn main() i32 { return 42; }

// Test: Load compilation unit
unit = CompilationUnit.init(allocator, "test.mini")
unit.load(arena)

assert unit.source.contains("fn main")
assert unit.tree.root.decls.len == 1
assert unit.tree.root.decls[0].fn_decl.name == "main"
```

### What This Enables

You can now load any source file into a compilation unit:

```
// Load main file
main_unit = CompilationUnit.init(allocator, "main.mini")
main_unit.load(arena)

// Load a library file
math_unit = CompilationUnit.init(allocator, "math.mini")
math_unit.load(arena)

// Both are now parsed and ready for code generation
```

---

## Summary: Complete CompilationUnit

```
┌────────────────────────────────────────────────────────────────────┐
│ CompilationUnit - Complete Implementation                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ CompilationUnit {                                                  │
│     path: string                                                   │
│     source: string                                                 │
│     tree: AST                                                      │
│     imports: Map<string, Import>                                   │
│     allocator: Allocator                                           │
│ }                                                                  │
│                                                                    │
│ Import {                                                           │
│     path: string                                                   │
│     namespace: string                                              │
│     unit: *CompilationUnit | null                                  │
│ }                                                                  │
│                                                                    │
│ Methods:                                                           │
│     init(allocator, path) -> CompilationUnit                       │
│     load(arena)           // Read file, parse AST                  │
│     extractImports(...)   // Coming in Module 3                    │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

We have the data structures, but we can't parse `import` statements yet. Let's add that syntax.

**Next: [Module 2: Import Statements](../02-imports/)** - Parse `import "file" as namespace;`

---

## Complete Code Reference

For a complete implementation, see:
- `src/unit.zig` - `CompilationUnit` and `Import` structs
