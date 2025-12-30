---
title: "Module 3: Loading Imports"
weight: 3
---

# Module 3: Loading Imports

We can parse import statements, but they don't actually load anything yet. This module teaches you to recursively load imported files while avoiding duplicates and infinite loops.

**What you'll build:**
- `extractImports()` to find import declarations in the AST
- `resolvePath()` to handle relative file paths
- `loadImports()` with recursive loading
- Cycle detection using a `units_map`

---

## Sub-lesson 3.1: Extracting Imports from AST

### The Problem

After parsing, our AST contains import declarations. But our `CompilationUnit.imports` map is still empty.

```
Source: import "math.mini" as math;
        fn main() i32 { return 0; }

Parsed AST:
  Root {
    decls: [
      ImportDecl { path: "math.mini", namespace: "math" },  ← Need to find these!
      FnDecl { name: "main", ... }
    ]
  }

unit.imports = {}  ← Empty! We need to populate this.
```

We need to scan the AST and extract import declarations into the `imports` map.

### The Solution

Add an `extractImports()` method that iterates through declarations and picks out imports.

**Implementation:**

```
extractImports(self, allocator) {
    // Walk through all declarations in the AST
    for decl in self.tree.root.decls {
        // Check if this declaration is an import
        if decl is import_decl {
            imp = decl.import_decl

            // Create Import struct and add to map
            self.imports.put(imp.namespace, Import {
                path: imp.path,
                namespace: imp.namespace,
                unit: null,  // Not loaded yet - will be filled later
            })
        }
        // Skip function declarations - we only want imports
    }
}
```

**Integration with load():**

```
load(self, arena) {
    // Step 1: Read source file
    self.source = read_file(self.path)

    // Step 2: Lex and parse
    lexer = Lexer.init(self.source)
    parser = Parser.init(arena.allocator(), &lexer)
    self.tree = parser.parse()

    // Step 3: NEW - Extract imports from parsed AST
    self.extractImports(arena.allocator())
}
```

**What Happens:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXTRACT IMPORTS FLOW                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Input AST:                                                          │
│   Root { decls: [ImportDecl, ImportDecl, FnDecl, FnDecl] }         │
│                                                                     │
│ After extractImports():                                             │
│   unit.imports = {                                                  │
│       "math"  → Import { path: "math.mini",  unit: null },         │
│       "utils" → Import { path: "utils.mini", unit: null },         │
│   }                                                                 │
│                                                                     │
│ Note: unit pointers are NULL - files not loaded yet!                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Implement `extractImports()` method
2. Call it at the end of `load()`
3. Test:

```
// Test: Extract single import
input = '''
import "math.mini" as math;
fn main() i32 { return 0; }
'''

unit = CompilationUnit.init(allocator, "test.mini")
unit.source = input
unit.tree = parse(input)
unit.extractImports(allocator)

assert unit.imports.count() == 1
assert unit.imports.get("math").path == "math.mini"
assert unit.imports.get("math").unit == null  // Not loaded yet

// Test: Extract multiple imports
input = '''
import "math.mini" as math;
import "utils.mini" as u;
fn main() i32 { return 0; }
'''

unit.tree = parse(input)
unit.imports.clear()
unit.extractImports(allocator)

assert unit.imports.count() == 2
assert unit.imports.get("math").path == "math.mini"
assert unit.imports.get("u").path == "utils.mini"
```

### What This Enables

After parsing and extracting, you know exactly what files need to be loaded:

```
// main.mini
import "math.mini" as math;
import "lib/utils.mini" as utils;

After load() + extractImports():
  unit.imports = {
      "math"  → { path: "math.mini", unit: null },
      "utils" → { path: "lib/utils.mini", unit: null },
  }

Next step: Actually load these files!
```

---

## Sub-lesson 3.2: Resolving Relative Paths

### The Problem

Import paths are relative to the importing file, not the compiler's working directory.

```
Project structure:
  project/
    main.mini           ← Compiler runs from here
    tests/
      test_main.mini    ← Contains: import "helper.mini" as h;
      helper.mini       ← This is what we want to load

When test_main.mini imports "helper.mini":
  - Wrong: "helper.mini" (doesn't exist in project/)
  - Right: "tests/helper.mini" (relative to test_main.mini)
```

We need to resolve import paths relative to the file that contains the import.

### The Solution

Create a `resolvePath()` function that combines the importing file's directory with the import path.

**Algorithm:**

```
resolvePath(base_path, import_path) -> string {
    // Step 1: Find the directory of the base file
    // "tests/main.mini" → "tests/"
    // "main.mini" → "" (no directory)

    dir_end = 0
    for i, char in base_path {
        if char == '/' {
            dir_end = i + 1  // Include the slash
        }
    }

    // Step 2: If no directory, return import path as-is
    if dir_end == 0 {
        return import_path
    }

    // Step 3: Combine directory + import path
    dir = base_path[0 .. dir_end]
    return concat(dir, import_path)
}
```

**Examples:**

```
┌────────────────────────────────────────────────────────────────────┐
│ PATH RESOLUTION EXAMPLES                                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ Base Path              Import Path       Resolved Path             │
│ ─────────────────────  ───────────────   ─────────────────────     │
│ "tests/main.mini"      "math.mini"       "tests/math.mini"         │
│ "main.mini"            "math.mini"       "math.mini"               │
│ "src/core/app.mini"    "utils.mini"      "src/core/utils.mini"     │
│ "main.mini"            "lib/utils.mini"  "lib/utils.mini"          │
│ "tests/main.mini"      "lib/io.mini"     "tests/lib/io.mini"       │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Why Not Use Absolute Paths?**

Relative paths are simpler and more portable:
- No need to know the project root
- Works when the project moves to a different directory
- Matches how most languages handle imports

### Try It Yourself

1. Implement `resolvePath()`
2. Test:

```
// Test: File in subdirectory
assert resolvePath("tests/main.mini", "math.mini") == "tests/math.mini"

// Test: File in root
assert resolvePath("main.mini", "math.mini") == "math.mini"

// Test: Deep path
assert resolvePath("src/core/app.mini", "utils.mini") == "src/core/utils.mini"

// Test: Import with directory
assert resolvePath("main.mini", "lib/utils.mini") == "lib/utils.mini"

// Test: Import with directory from subdirectory
assert resolvePath("tests/main.mini", "lib/io.mini") == "tests/lib/io.mini"
```

### What This Enables

Import paths now work correctly regardless of file location:

```
// tests/test_main.mini
import "helper.mini" as h;  // Loads "tests/helper.mini"

// src/app.mini
import "utils.mini" as u;   // Loads "src/utils.mini"
```

---

## Sub-lesson 3.3: Recursive Loading

### The Problem

A file can import another file, which imports another file, and so on:

```
main.mini
  └── imports utils.mini
        └── imports helpers.mini
              └── imports common.mini

We need to load ALL of these, not just direct imports.
```

Loading must be recursive: when we load a file, we also need to load its imports, and their imports, etc.

### The Solution

Create a `loadImports()` method that:
1. For each import in the current unit
2. Create a new `CompilationUnit` for the imported file
3. Load and parse that file
4. Recursively call `loadImports()` on the new unit

**Implementation:**

```
loadImports(self, arena, units_map) {
    allocator = arena.allocator()

    // Iterate through our imports
    for entry in self.imports.entries() {
        import = entry.value
        import_path = import.path

        // Resolve path relative to this file
        resolved = resolvePath(self.path, import_path)

        // Create new compilation unit
        new_unit = allocator.create(CompilationUnit)
        new_unit.* = CompilationUnit.init(allocator, resolved)

        // Load and parse the file
        new_unit.load(arena)

        // Link our Import to the loaded unit
        import.unit = new_unit

        // RECURSIVE: Load this unit's imports too!
        new_unit.loadImports(arena, units_map)
    }
}
```

**Loading Flow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ RECURSIVE LOADING FLOW                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ loadImports(main_unit):                                             │
│   │                                                                 │
│   ├─► Found import: "math.mini" as math                             │
│   │   ├─► Create math_unit                                          │
│   │   ├─► Load & parse math.mini                                    │
│   │   ├─► Link: main.imports["math"].unit = &math_unit              │
│   │   └─► loadImports(math_unit):  ← RECURSIVE                      │
│   │       └─► (math.mini has no imports, done)                      │
│   │                                                                 │
│   └─► Found import: "utils.mini" as utils                           │
│       ├─► Create utils_unit                                         │
│       ├─► Load & parse utils.mini                                   │
│       ├─► Link: main.imports["utils"].unit = &utils_unit            │
│       └─► loadImports(utils_unit):  ← RECURSIVE                     │
│           └─► Found import: "helpers.mini" as helpers               │
│               ├─► Create helpers_unit                               │
│               ├─► Load & parse helpers.mini                         │
│               └─► loadImports(helpers_unit): ...                    │
│                                                                     │
│ Result: All files in the dependency tree are loaded!                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Usage in Main Compiler:**

```
compile(path) -> string {
    arena = ArenaAllocator.init(allocator)
    defer arena.deinit()

    // Create and load main unit
    main_unit = CompilationUnit.init(arena.allocator(), path)
    main_unit.load(arena)

    // Load all imports (recursively)
    units_map = Map<string, *CompilationUnit>{}
    main_unit.loadImports(arena, units_map)

    // Now all units are loaded and linked!
    // Next: generate program from all units
    ...
}
```

### Try It Yourself

1. Implement `loadImports()` method
2. Create test files:

```
// Create files on disk:

// main.mini
import "math.mini" as math;
fn main() i32 { return 0; }

// math.mini
fn add(a: i32, b: i32) i32 { return a + b; }
```

3. Test:

```
// Test: Direct import loaded
main_unit = CompilationUnit.init(allocator, "main.mini")
main_unit.load(arena)
main_unit.loadImports(arena, units_map)

assert main_unit.imports.get("math").unit != null
assert main_unit.imports.get("math").unit.path == "math.mini"
```

4. Create nested imports:

```
// utils.mini
import "helpers.mini" as helpers;
fn format() { ... }

// helpers.mini
fn helper() { ... }

// main.mini
import "utils.mini" as utils;
fn main() { ... }
```

5. Test nested loading:

```
main_unit.load(arena)
main_unit.loadImports(arena, units_map)

// Check utils is loaded
utils_unit = main_unit.imports.get("utils").unit
assert utils_unit != null

// Check helpers is loaded through utils
helpers_unit = utils_unit.imports.get("helpers").unit
assert helpers_unit != null
```

### What This Enables

Deep dependency trees load automatically:

```
main.mini → utils.mini → helpers.mini → common.mini

After loadImports(main_unit):
  - main_unit.imports["utils"].unit → utils_unit
  - utils_unit.imports["helpers"].unit → helpers_unit
  - helpers_unit.imports["common"].unit → common_unit

All files parsed and linked!
```

---

## Sub-lesson 3.4: Preventing Circular Imports

### The Problem

What if two files import each other?

```
// a.mini
import "b.mini" as b;
fn funcA() { ... }

// b.mini
import "a.mini" as a;
fn funcB() { ... }
```

Without protection, loading causes infinite recursion:

```
loadImports(a_unit):
  → Load b.mini
    → loadImports(b_unit):
      → Load a.mini
        → loadImports(a_unit):  ← INFINITE LOOP!
          → Load b.mini
            → ...
```

We need to track which files are already loaded.

### The Solution

Use a `units_map` to remember loaded files. Before loading a file, check if it's already in the map.

**Updated loadImports:**

```
loadImports(self, arena, units_map) {
    allocator = arena.allocator()

    for entry in self.imports.entries() {
        import = entry.value
        import_path = import.path

        // Resolve path relative to this file
        resolved = resolvePath(self.path, import_path)

        // CHECK: Already loaded?
        if units_map.get(resolved) is existing_unit {
            // Reuse existing unit, don't load again!
            import.unit = existing_unit
            continue  // Skip to next import
        }

        // Not loaded yet - create and load
        new_unit = allocator.create(CompilationUnit)
        new_unit.* = CompilationUnit.init(allocator, resolved)
        new_unit.load(arena)

        // ADD TO MAP immediately (before recursive call!)
        units_map.put(resolved, new_unit)

        // Link to import
        import.unit = new_unit

        // Recursive call - safe because we're in the map
        new_unit.loadImports(arena, units_map)
    }
}
```

**Critical: Add to Map BEFORE Recursive Call**

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHY ADD TO MAP BEFORE RECURSION?                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ WRONG ORDER (add after recursion):                                  │
│   1. Load a.mini                                                    │
│   2. Recurse into a's imports                                       │
│   3. Load b.mini                                                    │
│   4. Recurse into b's imports                                       │
│   5. Try to load a.mini - NOT IN MAP YET! → infinite loop           │
│                                                                     │
│ RIGHT ORDER (add before recursion):                                 │
│   1. Load a.mini                                                    │
│   2. ADD a.mini TO MAP                                              │
│   3. Recurse into a's imports                                       │
│   4. Load b.mini                                                    │
│   5. ADD b.mini TO MAP                                              │
│   6. Recurse into b's imports                                       │
│   7. Try to load a.mini - FOUND IN MAP! → reuse existing            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Complete Example:**

```
Loading a.mini which imports b.mini which imports a.mini:

1. main: loadImports(a_unit, {})
   - units_map = {}

2. Found import: b.mini
   - Check map: b.mini not found
   - Load b.mini
   - units_map = { "a.mini": &a_unit, "b.mini": &b_unit }
   - Call: loadImports(b_unit, units_map)

3. Inside b_unit: Found import: a.mini
   - Check map: a.mini FOUND!
   - Reuse existing a_unit
   - No recursion needed

4. b_unit.loadImports() returns

5. a_unit.loadImports() returns

6. Done! No infinite loop.
```

**Alternative: Add Self to Map First**

Some implementations add the current unit to the map at the start of loading:

```
load(self, arena, units_map) {
    // Add ourselves to map FIRST
    units_map.put(self.path, self)

    // Read and parse
    self.source = read_file(self.path)
    self.tree = parse(self.source)
    self.extractImports()

    // Now safe to load imports
    self.loadImports(arena, units_map)
}
```

This also prevents cycles, but you need to pass `units_map` to `load()`.

### Try It Yourself

1. Update `loadImports()` with map checking
2. Create circular import test:

```
// Create files:

// a.mini
import "b.mini" as b;
fn funcA() i32 { return 1; }

// b.mini
import "a.mini" as a;
fn funcB() i32 { return 2; }
```

3. Test:

```
// Should NOT infinite loop!
a_unit = CompilationUnit.init(allocator, "a.mini")
a_unit.load(arena)

units_map = Map<string, *CompilationUnit>{}
units_map.put("a.mini", a_unit)  // Add ourselves first

a_unit.loadImports(arena, units_map)

// Both units should be loaded
assert units_map.contains("a.mini")
assert units_map.contains("b.mini")

// Cross-references should work
b_unit = a_unit.imports.get("b").unit
assert b_unit.imports.get("a").unit == a_unit  // Points back to original!
```

4. Test diamond dependency:

```
// main.mini imports both a.mini and b.mini
// a.mini imports common.mini
// b.mini imports common.mini

// common.mini should only be loaded ONCE
```

```
main_unit.loadImports(arena, units_map)

// Count how many times common.mini appears in map
// Should be exactly 1
common_count = 0
for path in units_map.keys() {
    if path.endsWith("common.mini") {
        common_count += 1
    }
}
assert common_count == 1
```

### What This Enables

Complex dependency graphs work correctly:

```
┌────────────────────────────────────────────────────────────────────┐
│ SUPPORTED DEPENDENCY PATTERNS                                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ Linear:        A → B → C → D                                       │
│                                                                    │
│ Diamond:           A                                               │
│                   / \                                              │
│                  B   C                                             │
│                   \ /                                              │
│                    D (loaded once!)                                │
│                                                                    │
│ Circular:      A ←→ B (both load, no infinite loop)                │
│                                                                    │
│ Complex:           A                                               │
│                  / | \                                             │
│                 B  C  D                                            │
│                 |\ | /|                                            │
│                 | \|/ |                                            │
│                 |  E  |                                            │
│                 | / \ |                                            │
│                 F     G (E, F, G each loaded once!)                │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Summary: Complete Import Loading

```
┌────────────────────────────────────────────────────────────────────┐
│ IMPORT LOADING - Complete Implementation                           │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ Methods:                                                           │
│   extractImports(allocator)                                        │
│     → Scans AST for ImportDecl nodes                               │
│     → Populates unit.imports map                                   │
│                                                                    │
│   resolvePath(base_path, import_path) -> string                    │
│     → Combines directory of base with import path                  │
│     → Handles relative imports correctly                           │
│                                                                    │
│   loadImports(arena, units_map)                                    │
│     → Loads each import recursively                                │
│     → Uses units_map to prevent duplicates and cycles              │
│     → Links Import.unit to loaded CompilationUnit                  │
│                                                                    │
│ Key Data:                                                          │
│   units_map: Map<string, *CompilationUnit>                         │
│     → Tracks all loaded files                                      │
│     → Prevents loading same file twice                             │
│     → Breaks circular import cycles                                │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

Files are loaded, but imported functions aren't usable yet. We need to prevent name collisions when combining multiple files.

**Next: [Module 4: Namespace Prefixing](../04-namespace-prefixing/)** - Prefix function names to avoid collisions

---

## Complete Code Reference

For a complete implementation, see:
- `src/unit.zig` - `extractImports()`, `loadImports()`
- `src/ast.zig` - `resolvePath()`
