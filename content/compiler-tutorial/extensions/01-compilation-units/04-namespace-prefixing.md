---
title: "1.4: Namespace Prefixing"
weight: 4
---

# Lesson 1.4: Namespace Prefixing

How do we prevent name collisions between files? By prefixing imported functions with their namespace.

---

## Goal

When generating code, prefix imported function names:
- `add` from namespace `math` becomes `math_add`

---

## The Problem

Without namespaces:

```
// math.mini
fn add(a, b) { return a + b; }

// string.mini
fn add(s1, s2) { return concat(s1, s2); }

// main.mini
import "math.mini";
import "string.mini";

fn main() {
    add(1, 2);  // Which add? Collision!
}
```

---

## The Solution

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         NAMESPACE PREFIXING                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   import "math.mini" as math;                                                │
│   import "string.mini" as str;                                               │
│                                                                              │
│   math.mini:add      →  math_add                                             │
│   string.mini:add    →  str_add                                              │
│                                                                              │
│   Now they're unique!                                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Implementation: generateProgram

When generating the final program, collect all functions and prefix imported ones:

```
generateProgram(self, allocator) -> Program {
    functions = []

    // Step 1: Add functions from THIS unit (no prefix)
    for decl in self.tree.root.decls {
        if decl is fn_decl {
            fn_ir = generateFunction(allocator, decl)
            functions.append(fn_ir)
        }
    }

    // Step 2: Add functions from IMPORTED units (with prefix)
    for entry in self.imports {
        namespace = entry.value.namespace
        unit = entry.value.unit

        if unit != null {
            for decl in unit.tree.root.decls {
                if decl is fn_decl {
                    fn_ir = generateFunction(allocator, decl)

                    // PREFIX THE NAME!
                    fn_ir.name = format("{}_{}", namespace, fn_ir.name)

                    functions.append(fn_ir)
                }
            }
        }
    }

    return Program { functions: functions }
}
```

---

## What Gets Generated

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         BEFORE AND AFTER                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   // math.mini                          // After generateProgram             │
│   fn add(a, b) { ... }                                                       │
│   fn square(n) { ... }       ────►      functions: [                         │
│                                           { name: "main", ... },             │
│   // main.mini                            { name: "math_add", ... },         │
│   import "math.mini" as math;             { name: "math_square", ... },      │
│   fn main() { ... }                     ]                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

All functions end up in one flat list. The namespace prefix ensures uniqueness.

---

## But Wait - Calling Still Broken!

We now have `math_add` as a function, but how do we call it?

Currently in main.mini:
```
fn main() i32 {
    return math_add(1, 2);  // We'd have to write this ugly name
}
```

We want to write:
```
fn main() i32 {
    return math.add(1, 2);  // Nice dot notation!
}
```

That's what the next lesson is for.

---

## Verify Your Implementation

### Test 1: Single imported function
```
// main.mini
import "math.mini" as math;
fn main() { return 0; }

// math.mini
fn add(a: i32, b: i32) i32 { return a + b; }

Program output:
  functions: [
    { name: "main" },
    { name: "math_add" }  // Prefixed!
  ]
```

### Test 2: Multiple imports
```
// main.mini
import "math.mini" as m;
import "utils.mini" as u;

// math.mini: fn add(), fn sub()
// utils.mini: fn helper()

Program output:
  functions: [
    { name: "main" },
    { name: "m_add" },
    { name: "m_sub" },
    { name: "u_helper" }
  ]
```

### Test 3: No prefix for local functions
```
// main.mini (no imports)
fn main() { return helper(); }
fn helper() { return 42; }

Program output:
  functions: [
    { name: "main" },     // No prefix
    { name: "helper" }    // No prefix
  ]
```

---

## What's Next

The functions are correctly named, but we can't call them with nice syntax yet. Let's add dot notation.

Next: [Lesson 1.5: Dot Notation](../05-dot-notation/) →
