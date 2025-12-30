---
title: "Module 4: Namespace Prefixing"
weight: 4
---

# Module 4: Namespace Prefixing

Files are loaded, but what happens when two files have functions with the same name? This module teaches you to prevent collisions by prefixing function names with their namespace.

**What you'll build:**
- Understanding of the name collision problem
- `generateProgram()` to collect all functions
- Multi-level prefixing for nested imports

---

## Sub-lesson 4.1: The Name Collision Problem

### The Problem

Different files might define functions with the same name:

```
// math.mini
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// string.mini
fn add(s1: string, s2: string) string {
    return concat(s1, s2);
}

// main.mini
import "math.mini" as math;
import "string.mini" as str;

fn main() i32 {
    add(1, 2);  // Which add? COLLISION!
}
```

When we combine these files, we have two functions named `add`. The compiler can't tell them apart.

### The Solution

Prefix each imported function with its namespace:

```
┌─────────────────────────────────────────────────────────────────────┐
│ NAMESPACE PREFIXING                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Original names:                                                     │
│   math.mini:   fn add(...)    → math_add                            │
│   string.mini: fn add(...)    → str_add                             │
│   main.mini:   fn main(...)   → main (no prefix - it's the entry)   │
│                                                                     │
│ After prefixing, all names are unique:                              │
│   - math_add                                                        │
│   - str_add                                                         │
│   - main                                                            │
│                                                                     │
│ The namespace comes from the import statement:                      │
│   import "math.mini" as math;    ← "math" is the prefix             │
│   import "string.mini" as str;   ← "str" is the prefix              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Why Underscore?**

We use `_` as the separator: `math_add`, not `math.add` or `math::add`.

Reasons:
1. Valid in most target languages (C, LLVM IR, assembly)
2. Won't conflict with our dot notation syntax (next module)
3. Simple and readable

### The Rule

```
Local functions (in the main file):     Keep original name
Imported functions:                     namespace + "_" + name
```

**Examples:**

| File | Function | Namespace | Final Name |
|------|----------|-----------|------------|
| main.mini | main | (local) | main |
| main.mini | helper | (local) | helper |
| math.mini | add | math | math_add |
| math.mini | square | math | math_square |
| utils.mini | format | u | u_format |

### Why Not Prefix Everything?

We could prefix local functions too (e.g., `main_main`), but:
1. The `main` function is special - linkers expect it by that name
2. Local functions don't collide with each other
3. Keeps output cleaner

### Try It Yourself

Think through these scenarios:

```
// Scenario 1: Same function in different namespaces
import "a.mini" as a;  // has fn helper()
import "b.mini" as b;  // has fn helper()

// Result: a_helper and b_helper (no collision)

// Scenario 2: Local function same name as imported
import "utils.mini" as utils;  // has fn format()
fn format() { ... }  // local function

// Result: format (local) and utils_format (imported)
// User must be careful which they call!

// Scenario 3: Short namespace
import "long/path/math.mini" as m;  // has fn calculate()

// Result: m_calculate (namespace from 'as', not path)
```

### What This Enables

Files can have identical function names without conflicts:

```
// Before prefixing (broken):
Program { functions: [main, add, add] }  // Which add?!

// After prefixing (works):
Program { functions: [main, math_add, str_add] }  // Clear!
```

---

## Sub-lesson 4.2: Implementing generateProgram

### The Problem

We have a tree of loaded `CompilationUnit`s. We need to flatten them into a single `Program` with all functions properly prefixed.

```
Loaded units:
  main_unit
    ├── imports["math"] → math_unit (functions: add, square)
    └── imports["utils"] → utils_unit (functions: helper)

Need to produce:
  Program {
    functions: [main, math_add, math_square, utils_helper]
  }
```

### The Solution

Create a `generateProgram()` method that:
1. Adds local functions (no prefix)
2. Walks imported units, adding their functions (with prefix)

**Implementation:**

```
generateProgram(self, allocator) -> Program {
    functions = ArrayList(Function)

    // Step 1: Add local functions (from this unit, no prefix)
    for decl in self.tree.root.decls {
        if decl is fn_decl {
            fn_ir = generateFunction(allocator, decl)
            // Keep original name - no prefix for local functions
            functions.append(fn_ir)
        }
    }

    // Step 2: Add imported functions (with namespace prefix)
    for entry in self.imports.entries() {
        namespace = entry.key        // e.g., "math"
        import = entry.value
        imported_unit = import.unit

        if imported_unit == null {
            continue  // Skip if not loaded
        }

        // Get functions from imported unit
        for decl in imported_unit.tree.root.decls {
            if decl is fn_decl {
                fn_ir = generateFunction(allocator, decl)

                // PREFIX THE NAME!
                original_name = fn_ir.name
                fn_ir.name = format("{}_{}", namespace, original_name)

                functions.append(fn_ir)
            }
        }
    }

    return Program { functions: functions }
}
```

**Visualization:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ generateProgram() FLOW                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ main_unit:                                                          │
│   tree.decls = [ImportDecl(math), FnDecl(main), FnDecl(helper)]    │
│   imports = { "math": Import { unit: math_unit } }                  │
│                                                                     │
│ math_unit:                                                          │
│   tree.decls = [FnDecl(add), FnDecl(square)]                       │
│                                                                     │
│ Step 1: Local functions                                             │
│   FnDecl(main)   → Function { name: "main" }                        │
│   FnDecl(helper) → Function { name: "helper" }                      │
│                                                                     │
│ Step 2: Imported functions (prefix with "math")                     │
│   FnDecl(add)    → Function { name: "math_add" }                    │
│   FnDecl(square) → Function { name: "math_square" }                 │
│                                                                     │
│ Result: Program {                                                   │
│   functions: [main, helper, math_add, math_square]                  │
│ }                                                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Usage in Compiler:**

```
compile(path) -> string {
    arena = ArenaAllocator.init(allocator)

    // Load main unit and all imports
    main_unit = CompilationUnit.init(arena.allocator(), path)
    main_unit.load(arena)
    main_unit.loadImports(arena, units_map)

    // Generate flat program with all functions
    program = main_unit.generateProgram(arena.allocator())

    // Generate output (LLVM IR, assembly, etc.)
    return codegen.generate(program)
}
```

### Try It Yourself

1. Implement `generateProgram()` method
2. Test with single import:

```
// Create files:

// main.mini
import "math.mini" as math;
fn main() i32 { return 0; }

// math.mini
fn add(a: i32, b: i32) i32 { return a + b; }
fn sub(a: i32, b: i32) i32 { return a - b; }
```

3. Test:

```
main_unit = CompilationUnit.init(allocator, "main.mini")
main_unit.load(arena)
main_unit.loadImports(arena, units_map)

program = main_unit.generateProgram(allocator)

// Check function count
assert program.functions.len == 3  // main, math_add, math_sub

// Check names
names = [fn.name for fn in program.functions]
assert "main" in names
assert "math_add" in names
assert "math_sub" in names
```

4. Test with multiple imports:

```
// main.mini
import "math.mini" as m;
import "utils.mini" as u;
fn main() i32 { return 0; }

// math.mini: fn add()
// utils.mini: fn helper()

program = main_unit.generateProgram(allocator)

names = [fn.name for fn in program.functions]
assert "main" in names
assert "m_add" in names
assert "u_helper" in names
```

### What This Enables

Multiple files compile into one program:

```
// Input: 3 separate files
main.mini  → functions: [main, localHelper]
math.mini  → functions: [add, square]
io.mini    → functions: [print, read]

// Output: 1 combined program
Program {
    functions: [
        main,
        localHelper,
        math_add,
        math_square,
        io_print,
        io_read
    ]
}
```

---

## Sub-lesson 4.3: Handling Nested Imports

### The Problem

What if an imported file imports other files?

```
// main.mini
import "utils.mini" as utils;
fn main() { ... }

// utils.mini
import "helpers.mini" as helpers;
fn format() { ... }

// helpers.mini
fn escape() { ... }
```

The dependency tree:
```
main.mini
  └── utils.mini
        └── helpers.mini
```

How should `escape` be named? Options:
1. `escape` - No prefix (wrong - collisions possible)
2. `helpers_escape` - Single prefix (wrong - from main's perspective, it's in utils)
3. `utils_helpers_escape` - Chain of prefixes (correct!)

### The Solution

Build up the prefix as you traverse the import tree.

**Updated generateProgram:**

```
generateProgram(self, allocator) -> Program {
    functions = ArrayList(Function)

    // Add local functions (no prefix)
    addLocalFunctions(self, allocator, functions)

    // Add imported functions with prefix chain
    addImportedFunctions(self, allocator, functions, prefix = "")

    return Program { functions: functions }
}

addLocalFunctions(unit, allocator, functions) {
    for decl in unit.tree.root.decls {
        if decl is fn_decl {
            fn_ir = generateFunction(allocator, decl)
            functions.append(fn_ir)
        }
    }
}

addImportedFunctions(unit, allocator, functions, prefix) {
    for entry in unit.imports.entries() {
        namespace = entry.key
        imported_unit = entry.value.unit

        if imported_unit == null {
            continue
        }

        // Build new prefix: existing_prefix + namespace
        new_prefix = if prefix == "" {
            namespace  // e.g., "utils"
        } else {
            format("{}_{}", prefix, namespace)  // e.g., "utils_helpers"
        }

        // Add functions from this imported unit
        for decl in imported_unit.tree.root.decls {
            if decl is fn_decl {
                fn_ir = generateFunction(allocator, decl)
                fn_ir.name = format("{}_{}", new_prefix, fn_ir.name)
                functions.append(fn_ir)
            }
        }

        // RECURSIVE: Handle this unit's imports with extended prefix
        addImportedFunctions(imported_unit, allocator, functions, new_prefix)
    }
}
```

**Visualization:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ NESTED IMPORT PREFIXING                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Import tree:                                                        │
│   main.mini                                                         │
│     └── utils.mini (as utils)                                       │
│           └── helpers.mini (as helpers)                             │
│                                                                     │
│ Prefix chain:                                                       │
│   main.mini functions:      no prefix                               │
│   utils.mini functions:     "utils_"                                │
│   helpers.mini functions:   "utils_helpers_"                        │
│                                                                     │
│ Result:                                                             │
│   fn main()     in main.mini     → main                             │
│   fn format()   in utils.mini    → utils_format                     │
│   fn escape()   in helpers.mini  → utils_helpers_escape             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Why Chain Prefixes?**

From `main.mini`'s perspective:
- `utils` is a direct import (namespace: `utils`)
- `helpers` is imported through `utils` (namespace: `utils_helpers`)

The prefixes reflect the import path from the main file.

**Alternative: Flat Prefixing**

Some compilers use simpler approaches:
- Only prefix direct imports (might cause collisions with transitive imports)
- Use full file paths as prefixes (verbose but safe)

The chained approach balances safety and readability.

### Avoiding Duplicates

With nested imports, a file might be reachable through multiple paths:

```
main.mini
  ├── a.mini (imports common.mini)
  └── b.mini (imports common.mini)

common.mini would be visited twice!
```

Solution: Track which units you've already processed:

```
addImportedFunctions(unit, allocator, functions, prefix, processed) {
    for entry in unit.imports.entries() {
        imported_unit = entry.value.unit

        // Skip if already processed
        if processed.contains(imported_unit) {
            continue
        }
        processed.add(imported_unit)

        // ... add functions ...

        // Recursive call
        addImportedFunctions(imported_unit, allocator, functions, new_prefix, processed)
    }
}
```

### Try It Yourself

1. Update `generateProgram()` for nested imports
2. Create test files:

```
// main.mini
import "utils.mini" as utils;
fn main() i32 { return 0; }

// utils.mini
import "helpers.mini" as h;
fn format() { ... }

// helpers.mini
fn escape() { ... }
fn clean() { ... }
```

3. Test:

```
main_unit.load(arena)
main_unit.loadImports(arena, units_map)

program = main_unit.generateProgram(allocator)

names = [fn.name for fn in program.functions]
assert "main" in names
assert "utils_format" in names
assert "utils_h_escape" in names  // Chained prefix!
assert "utils_h_clean" in names
```

4. Test diamond dependency:

```
// main.mini imports both a.mini and b.mini
// Both a.mini and b.mini import common.mini

// common.mini functions should appear ONCE in output
```

### What This Enables

Arbitrarily deep import hierarchies work correctly:

```
main.mini
  └── graphics.mini (as gfx)
        └── math.mini (as math)
              └── vector.mini (as vec)

Functions:
  main           (main.mini)
  gfx_draw       (graphics.mini)
  gfx_math_sin   (math.mini via graphics)
  gfx_math_vec_normalize  (vector.mini via math via graphics)
```

---

## Summary: Namespace Prefixing

```
┌────────────────────────────────────────────────────────────────────┐
│ NAMESPACE PREFIXING - Complete Implementation                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ Rule:                                                              │
│   Local functions:    No prefix                                    │
│   Direct imports:     namespace_functionName                       │
│   Nested imports:     outer_inner_functionName                     │
│                                                                    │
│ Method:                                                            │
│   generateProgram(allocator) -> Program                            │
│     1. Add local functions (no prefix)                             │
│     2. Recursively add imported functions (with prefix chain)      │
│     3. Track processed units to avoid duplicates                   │
│                                                                    │
│ Example:                                                           │
│   main.mini imports utils.mini (as u)                              │
│   utils.mini imports helpers.mini (as h)                           │
│                                                                    │
│   main.mini:main        → main                                     │
│   utils.mini:format     → u_format                                 │
│   helpers.mini:escape   → u_h_escape                               │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

Functions are correctly prefixed, but we have to write `math_add(1, 2)` which is ugly. Let's add dot notation so we can write `math.add(1, 2)` instead.

**Next: [Module 5: Dot Notation](../05-dot-notation/)** - Beautiful calling syntax for imported functions

---

## Complete Code Reference

For a complete implementation, see:
- `src/unit.zig` - `generateProgram()`, `addImportedFunctions()`
