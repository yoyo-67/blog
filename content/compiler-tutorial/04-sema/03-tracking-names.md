---
title: "4.3: Tracking Names"
weight: 3
---

# Lesson 4.3: Tracking Names

Map names to their types.

---

## The Problem

When we see `decl_ref("x")`, we need to know:
1. Does "x" exist?
2. What type is "x"?

This requires tracking what names are declared and their types.

---

## Two Data Structures

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         TRACKING DATA                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   names: HashMap<string, type>                                               │
│   ┌─────────┬────────┐                                                       │
│   │  "a"    │  i32   │  ← parameter                                          │
│   │  "b"    │  i64   │  ← parameter                                          │
│   │  "x"    │  i32   │  ← local variable                                     │
│   └─────────┴────────┘                                                       │
│                                                                              │
│   inst_types: []?Type                                                        │
│   ┌───┬───┬───┬───┬───┐                                                      │
│   │i32│i32│i32│nil│nil│  ← type of each instruction's result                 │
│   └───┴───┴───┴───┴───┘                                                      │
│     %0  %1  %2  %3  %4                                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## names: What's Declared

```
names: HashMap<string, type>

Purpose: Track declared names and their types

Operations:
  - put("x", i32)     → Register x as type i32
  - get("x")          → Returns i32 or null if not found
  - contains("x")     → Returns true/false
```

---

## inst_types: Instruction Results

```
inst_types: []?Type

Purpose: Track the result type of each instruction

Index matches instruction number:
  inst_types[0] = type of %0
  inst_types[1] = type of %1
  ...

Some instructions have no result type (null):
  - decl (declaration doesn't produce a value)
  - return_stmt (returns, doesn't produce a value)
```

---

## Initializing: Register Parameters

Before analyzing instructions, register function parameters:

```
function analyzeFunction(func):
    names = {}
    inst_types = []

    // Parameters are already declared
    for param in func.params:
        names.put(param.name, param.type)

    // Now analyze instructions...
```

Example:
```
fn add(a: i32, b: i64) i32 { ... }

After initialization:
  names = { "a": i32, "b": i64 }
```

---

## Processing Each Instruction

Walk through instructions and determine types:

```
for i in 0..instruction_count:
    inst = instruction_at(i)

    result_type = switch inst:
        constant:
            "i32"                    // Literals are i32

        param_ref(idx):
            func.params[idx].type    // Type from signature

        decl(name, value):
            // Handle declaration (next lesson)
            null                     // Decl has no result type

        decl_ref(name):
            // Look up name (next lesson)
            names.get(name)          // Type from symbol table

        add, sub, mul, div:
            // Binary ops use operand types
            null                     // We'll skip this for now

        return_stmt:
            null                     // Return has no result type

    inst_types.append(result_type)
```

---

## Example: Step by Step

```
Source:
fn calc(n: i32) i32 {
    const doubled = n * 2;
    return doubled;
}

ZIR:
  %0 = param_ref(0)
  %1 = constant(2)
  %2 = mul(%0, %1)
  %3 = decl("doubled", %2)
  %4 = decl_ref("doubled")
  %5 = ret(%4)
```

---

## Step 1: Initialize

```
names = { "n": i32 }       // From parameters
inst_types = []
```

---

## Step 2: Process %0 = param_ref(0)

```
param_ref(0) → params[0] = n → type: i32

names = { "n": i32 }
inst_types = [i32]
              ─┬─
              %0
```

---

## Step 3: Process %1 = constant(2)

```
constant(2) → type: i32

names = { "n": i32 }
inst_types = [i32, i32]
              ─┬─  ─┬─
              %0   %1
```

---

## Step 4: Process %2 = mul(%0, %1)

```
mul(%0, %1) → (we'll treat as null for now)

names = { "n": i32 }
inst_types = [i32, i32, null]
              ─┬─  ─┬─  ─┬──
              %0   %1   %2
```

---

## Step 5: Process %3 = decl("doubled", %2)

```
decl("doubled", %2):
  - Register "doubled" in names
  - Get value type from inst_types[2] (or default to i32)

names = { "n": i32, "doubled": i32 }
inst_types = [i32, i32, null, null]
              ─┬─  ─┬─  ─┬── ─┬──
              %0   %1   %2   %3
```

---

## Step 6: Process %4 = decl_ref("doubled")

```
decl_ref("doubled"):
  - Lookup "doubled" in names
  - Found: type is i32

names = { "n": i32, "doubled": i32 }
inst_types = [i32, i32, null, null, i32]
              ─┬─  ─┬─  ─┬── ─┬── ─┬─
              %0   %1   %2   %3   %4
```

---

## Step 7: Process %5 = ret(%4)

```
ret(%4):
  - Return statement has no result type

names = { "n": i32, "doubled": i32 }
inst_types = [i32, i32, null, null, i32, null]
              ─┬─  ─┬─  ─┬── ─┬── ─┬─  ─┬──
              %0   %1   %2   %3   %4   %5
```

---

## Type Inference for Declarations

When declaring a variable, we infer its type from the value:

```
const x = 10;        // x is i32 (from constant)
const y = x;         // y is i32 (from x)
const z = a + b;     // z is i32 (from addition result)
```

Implementation:
```
decl(name, value):
    value_type = inst_types[value]
    if value_type == null:
        value_type = "i32"      // Default fallback

    names.put(name, value_type)
    result_type = null          // Decl has no result
```

---

## Summary: The Two Tables

```
┌──────────────────────────────────────────────────────────────────────────────┐
│   names                                                                      │
│   ───────────────────────────────────                                        │
│   Use: Check if variable exists                                              │
│   Use: Get variable's type                                                   │
│   Updated: When processing decl                                              │
│   Initialized: With function parameters                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│   inst_types                                                                 │
│   ───────────────────────────────────                                        │
│   Use: Get result type of any instruction                                    │
│   Use: Infer type for declarations                                           │
│   Updated: After processing each instruction                                 │
│   Initialized: Empty array                                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Pseudo Code Summary

```
function analyzeFunction(func):
    names = {}
    inst_types = []

    // Register parameters
    for param in func.params:
        names.put(param.name, param.type)

    // Analyze each instruction
    for i in 0..func.instructionCount():
        inst = func.instructionAt(i)

        result_type = switch inst:
            constant     → "i32"
            param_ref(n) → func.params[n].type
            decl_ref(n)  → names.get(n)
            decl(n, v)   → (register name, return null)
            others       → null

        inst_types.append(result_type)
```

---

## What's Next

Now let's use these data structures to detect undefined variables.

Next: [Lesson 4.4: Undefined Variables](../04-undefined-vars/) →
