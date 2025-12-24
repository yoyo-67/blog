---
title: "4.5: Duplicate Declarations"
weight: 5
---

# Lesson 4.5: Duplicate Declarations

Detect when the same name is declared twice.

---

## The Error

```
fn foo() i32 {
    const x = 1;
    const x = 2;        // x already declared!
    return x;
}
```

Expected output:
```
1:31: error: duplicate declaration "x"
fn foo() i32 { const x = 1; const x = 2; return x; }
                                  ^
```

---

## When to Check

Check when processing `decl` instructions:

```
ZIR: %2 = decl("x", %1)

Question: Is "x" already in our names table?
  - Yes → error: duplicate declaration
  - No  → register "x" with its type
```

---

## The Check

```
decl(name, value):
    if names.contains(name):
        error: duplicate declaration "name"
    else:
        // Infer type from value
        value_type = inst_types[value] or "i32"
        names.put(name, value_type)

    return null     // decl has no result type
```

---

## Error Data Structure

Add a new error variant:

```
Error = union {
    undefined_variable: struct {
        name: []const u8,
        inst: *const Instruction,
    },

    duplicate_declaration: struct {
        name: []const u8,
        inst: *const Instruction,
    },
}
```

---

## Getting the Token

Different error types follow different paths:

```
function getToken(error):
    switch error:
        undefined_variable:
            // decl_ref → identifier_ref → token
            return error.inst.decl_ref.node.identifier_ref.token

        duplicate_declaration:
            // decl → identifier → token
            return error.inst.decl.node.identifier.token
```

---

## Getting the Message

```
function getMessage(error):
    switch error:
        undefined_variable:
            return "undefined variable \"{error.name}\""

        duplicate_declaration:
            return "duplicate declaration \"{error.name}\""
```

---

## Complete Check in analyzeFunction

```
function analyzeFunction(func):
    errors = []
    names = {}
    inst_types = []

    // Register parameters (they count as declarations!)
    for param in func.params:
        names.put(param.name, param.type)

    for i in 0..instruction_count:
        inst = instruction_at(i)

        result_type = switch inst:
            constant:
                "i32"

            param_ref(idx):
                func.params[idx].type

            decl(d):
                if names.contains(d.name):
                    errors.append({
                        duplicate_declaration: {
                            name: d.name,
                            inst: inst
                        }
                    })
                else:
                    value_type = inst_types[d.value] or "i32"
                    names.put(d.name, value_type)
                null

            decl_ref(d):
                names.get(d.name) or {
                    errors.append({
                        undefined_variable: {
                            name: d.name,
                            inst: inst
                        }
                    })
                    null
                }

            // ... other cases ...

        inst_types.append(result_type)

    return errors
```

---

## Parameters Are Declarations

Parameters are pre-registered, so they also block re-declaration:

```
fn foo(x: i32) i32 {
    const x = 10;       // Error! x is already a parameter
    return x;
}
```

After registering params:
```
names = { "x": i32 }
```

When processing `decl("x", ...)`:
```
names.contains("x") → true → Error!
```

---

## Type Inference Still Works

Even if we report an error, we can still register the name:

```
fn foo() i32 {
    const x = 1;
    const x = 2;        // Error reported, but...
    return x;           // ...we still know x exists
}
```

Option 1: Don't register duplicate (stricter)
```
// Second x is not registered
// "return x" uses first x
```

Option 2: Overwrite (allows continued analysis)
```
// Second x overwrites first
// "return x" uses second x
```

We'll use Option 1 - don't register duplicates.

---

## Example: Step by Step

```
Source:
fn foo() i32 { const x = 1; const x = 2; return x; }

ZIR:
    %0 = constant(1)
    %1 = decl("x", %0)
    %2 = constant(2)
    %3 = decl("x", %2)      ← This is the duplicate!
    %4 = decl_ref("x")
    %5 = ret(%4)
```

Processing:
```
Step 1: names = {}
        %0 = constant(1) → i32
        inst_types = [i32]

Step 2: %1 = decl("x", %0)
        names.contains("x") → false
        names.put("x", i32)
        names = {"x": i32}
        inst_types = [i32, null]

Step 3: %2 = constant(2) → i32
        inst_types = [i32, null, i32]

Step 4: %3 = decl("x", %2)
        names.contains("x") → true
        ERROR: duplicate declaration "x"
        (don't update names)
        inst_types = [i32, null, i32, null]

Step 5: %4 = decl_ref("x")
        names.get("x") → i32
        inst_types = [i32, null, i32, null, i32]

Step 6: %5 = ret(%4)
        inst_types = [i32, null, i32, null, i32, null]

Final: errors = [duplicate_declaration("x")]
```

---

## Verify Your Implementation

### Test 1: Simple duplicate
```
Source: fn foo() i32 { const x = 1; const x = 2; return x; }
Error: "duplicate declaration \"x\"" at col 31
```

### Test 2: Parameter shadows
```
Source: fn foo(x: i32) i32 { const x = 10; return x; }
Error: "duplicate declaration \"x\""
```

### Test 3: Different names are fine
```
Source: fn foo() i32 { const x = 1; const y = 2; return x + y; }
Errors: (none)
```

### Test 4: Multiple duplicates
```
Source: fn foo() i32 { const x = 1; const x = 2; const x = 3; return x; }
Errors: 2 duplicate declaration errors
```

---

## No Shadowing (Our Design Choice)

Some languages allow shadowing:

```
// Rust allows this:
let x = 1;
let x = 2;      // New x shadows old x
```

Our mini language does not:

```
// Our language:
const x = 1;
const x = 2;    // Error: duplicate declaration
```

This is a design choice. Either is valid.

---

## What's Next

Now let's add return types to functions.

Next: [Lesson 4.6: Return Type Declaration](../06-return-type-decl/) →
