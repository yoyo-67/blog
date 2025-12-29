---
title: "1.3: Loading Imports"
weight: 3
---

# Lesson 1.3: Loading Imports

Now let's actually load the imported files.

---

## Goal

Implement the logic to:
1. Extract imports from a parsed AST
2. Load imported files recursively
3. Avoid loading the same file twice

---

## The Loading Process

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         IMPORT LOADING FLOW                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   main.mini                                                                  │
│      │                                                                       │
│      ▼                                                                       │
│   1. Parse main.mini                                                         │
│      │                                                                       │
│      ▼                                                                       │
│   2. Extract imports: ["math.mini" as math]                                  │
│      │                                                                       │
│      ▼                                                                       │
│   3. For each import:                                                        │
│      ├── Resolve path relative to main.mini                                  │
│      ├── Check if already loaded (avoid duplicates)                          │
│      ├── Load and parse the file                                             │
│      └── Recursively load ITS imports                                        │
│      │                                                                       │
│      ▼                                                                       │
│   4. Link: main.imports["math"].unit = &math_unit                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Extract Imports

After parsing, scan the AST for import declarations:

```
extractImports(self, allocator) {
    for decl in self.tree.root.decls {
        if decl is import_decl {
            imp = decl.import_decl
            self.imports.put(imp.namespace, Import {
                path: imp.path,
                namespace: imp.namespace,
                unit: null,  // Not loaded yet
            })
        }
    }
}
```

Call this at the end of `load()`:

```
load(self, arena) {
    // Read source file
    self.source = read_file(self.path)

    // Parse into AST
    self.tree = parse(self.source)

    // NEW: Extract imports
    self.extractImports(arena.allocator())
}
```

---

## Step 2: Resolve Paths

Imports are relative to the importing file:

```
// If main.mini is at "tests/main.mini"
// and it imports "math.mini"
// The resolved path is "tests/math.mini"

resolvePath(allocator, base_path, import_path) -> string {
    // Get directory of base file
    if last_index_of(base_path, "/") is idx {
        dir = base_path[0 .. idx + 1]  // Include the slash
        return format("{}{}", dir, import_path)
    }
    // No directory, use import path as-is
    return import_path
}
```

Examples:
- `resolvePath("tests/main.mini", "math.mini")` → `"tests/math.mini"`
- `resolvePath("main.mini", "lib/utils.mini")` → `"lib/utils.mini"`

---

## Step 3: Load Imports Recursively

```
loadImports(self, arena, units_map) {
    allocator = arena.allocator()

    for entry in self.imports {
        import_path = entry.value.path

        // Check if already loaded (avoid duplicates!)
        if units_map.get(import_path) is existing {
            entry.value.unit = existing
            continue
        }

        // Resolve path relative to current file
        resolved_path = resolvePath(allocator, self.path, import_path)

        // Create and load new compilation unit
        unit = allocator.create(CompilationUnit)
        unit.* = CompilationUnit.init(allocator, resolved_path)
        unit.load(arena)

        // Add to global units map
        units_map.put(import_path, unit)

        // Link to our import
        entry.value.unit = unit

        // RECURSIVE: Load this unit's imports too
        unit.loadImports(arena, units_map)
    }
}
```

---

## Step 4: Update Main Compiler

In your main compilation function:

```
compileUnit(allocator, path) -> string {
    arena = ArenaAllocator.init(allocator)
    defer arena.deinit()

    // Create main compilation unit
    unit = CompilationUnit.init(arena.allocator(), path)
    unit.load(arena)

    // NEW: Load all imports
    units_map = empty_map()
    unit.loadImports(arena, units_map)

    // Generate program (next lesson)
    program = unit.generateProgram(arena.allocator())

    // Generate output
    return codegen.generate(program)
}
```

---

## Handling Circular Imports

The `units_map` prevents infinite loops:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         CIRCULAR IMPORT HANDLING                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   a.mini imports b.mini                                                      │
│   b.mini imports a.mini                                                      │
│                                                                              │
│   Loading a.mini:                                                            │
│     1. units_map = {}                                                        │
│     2. Add a.mini to map: { "a.mini": &a_unit }                              │
│     3. Load b.mini (a's import)                                              │
│     4. Add b.mini to map: { "a.mini": &a_unit, "b.mini": &b_unit }           │
│     5. b.mini tries to import a.mini                                         │
│     6. a.mini ALREADY IN MAP → reuse existing, don't reload                  │
│     7. No infinite loop!                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Implementation

### Test 1: Single import
```
// main.mini
import "math.mini";
fn main() { return 0; }

// math.mini
fn add(a: i32, b: i32) i32 { return a + b; }

Check: main_unit.imports["math"].unit != null
       main_unit.imports["math"].unit.path == "math.mini"
```

### Test 2: Nested imports
```
// main.mini imports utils.mini
// utils.mini imports helpers.mini

Check: All three units loaded
       No duplicates in units_map
```

### Test 3: Path resolution
```
// tests/main.mini imports "math.mini"

Check: Resolved path is "tests/math.mini"
```

---

## What's Next

We can load imports, but the imported functions aren't usable yet. Let's add namespace prefixing.

Next: [Lesson 1.4: Namespace Prefixing](../04-namespace-prefixing/) →
