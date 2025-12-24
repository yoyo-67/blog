---
title: "4.7: Return Type Checking"
weight: 7
---

# Lesson 4.7: Return Type Checking

Verify that return statements match the declared type.

---

## The Error

```
fn foo() i32 {
    return true;        // Returns bool, expected i32!
}
```

Expected output:
```
1:12: error: return type mismatch: expected i32, got bool
fn foo() i32 { return true; }
           ^
```

---

## When to Check

Check when processing `return_stmt` instructions:

```
ZIR: %3 = ret(%2)

Questions:
  1. What type is the return value (%2)?
  2. What type does the function declare?
  3. Do they match?
```

---

## ZIR Return Statement

The return statement references another instruction:

```
Instruction = union {
    return_stmt: struct {
        value: InstructionRef,    // Points to the return value
        node: *const Node,        // For error location
    },
    // ...
}
```

---

## The Check

```
return_stmt(value):
    // Get the actual return type
    actual_type = inst_types[value]

    // Get the declared return type
    expected_type = func.return_type

    // Compare
    if expected_type != null and actual_type != expected_type:
        error: return type mismatch

    return null     // return has no result type
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

    return_type_mismatch: struct {
        expected: []const u8,
        actual: []const u8,
        inst: *const Instruction,
    },
}
```

---

## Getting the Token

For return type mismatch, point to the return statement:

```
function getToken(error):
    switch error:
        undefined_variable:
            return error.inst.decl_ref.node.identifier_ref.token

        duplicate_declaration:
            return error.inst.decl.node.identifier.token

        return_type_mismatch:
            return error.inst.return_stmt.node.return_stmt.token
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

        return_type_mismatch:
            return "return type mismatch: expected {expected}, got {actual}"
```

---

## Complete Check

```
function analyzeFunction(func):
    errors = []
    names = {}
    inst_types = []

    // Register parameters
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
                // ... duplicate check ...

            decl_ref(d):
                // ... undefined check ...

            return_stmt(r):
                // NEW: Check return type
                actual_type = inst_types[r.value]

                if func.return_type != null:
                    if actual_type != null and actual_type != func.return_type:
                        errors.append({
                            return_type_mismatch: {
                                expected: func.return_type,
                                actual: actual_type,
                                inst: inst
                            }
                        })

                null    // return has no result type

            // ... other cases ...

        inst_types.append(result_type)

    return errors
```

---

## Type Inference (When No Declaration)

If the function has no declared return type, infer it:

```
fn add(a: i32, b: i32) {    // No return type declared
    return a + b;            // Returns i32
}
```

Two approaches:

**Approach 1: Store inferred type**
```
if func.return_type == null:
    func.return_type = actual_type
```

**Approach 2: Just skip the check**
```
if func.return_type == null:
    // No declared type, no check needed
    skip
```

We'll use Approach 1 to capture the inferred type.

---

## Multiple Return Statements

A function can have multiple returns:

```
fn abs(n: i32) i32 {
    if n < 0:
        return -n;      // First return
    return n;           // Second return
}
```

All must match the declared type:

```
for each return_stmt:
    if actual_type != expected_type:
        error
```

---

## Void Functions

Functions without a return type are void:

```
fn greet() {
    // No return statement needed
}

fn greet2() {
    return;             // Explicit void return
}
```

For void functions:
- `return;` (no value) is valid
- `return 42;` is invalid (returning non-void)

---

## Handling Void Returns

```
return_stmt(r):
    if r.value == null:
        // Void return: return;
        actual_type = "void"
    else:
        actual_type = inst_types[r.value]

    if func.return_type == null:
        expected_type = "void"
    else:
        expected_type = func.return_type

    if actual_type != expected_type:
        error
```

---

## Example: Step by Step

```
Source:
fn foo(a: i32, b: i64) i32 {
    return a + b;
}

ZIR:
    function "foo":
        params: [("a", i32), ("b", i64)]
        return_type: i32
        %0 = param_ref(0)      // a: i32
        %1 = param_ref(1)      // b: i64
        %2 = add(%0, %1)       // ???
        %3 = ret(%2)
```

Analysis:
```
Step 1: names = {"a": i32, "b": i64}

Step 2: %0 = param_ref(0) → i32
        inst_types = [i32]

Step 3: %1 = param_ref(1) → i64
        inst_types = [i32, i64]

Step 4: %2 = add(%0, %1) → null (or i32 if we track it)
        inst_types = [i32, i64, null]

Step 5: %3 = ret(%2)
        actual_type = inst_types[2] = null or i32
        expected_type = func.return_type = "i32"

        If we tracked add result as i32:
            i32 == i32 ✓ No error

        If add result is null:
            Skip check (can't determine type)
```

---

## Tracking Binary Op Types (Optional)

To properly check `a + b`, we need to track binary op result types:

```
add(lhs, rhs):
    lhs_type = inst_types[lhs]
    rhs_type = inst_types[rhs]

    // For now, assume both are same type
    if lhs_type == rhs_type:
        return lhs_type
    else:
        // Type mismatch in addition
        return null  // or error
```

This extends our type tracking system.

---

## Verify Your Implementation

### Test 1: Matching types
```
Source: fn foo() i32 { return 42; }
Errors: (none)
```

### Test 2: Mismatched types
```
Source: fn foo() i32 { return true; }
Error: "return type mismatch: expected i32, got bool"
```

### Test 3: Parameter type matches
```
Source: fn foo(x: i32) i32 { return x; }
Errors: (none)
```

### Test 4: Parameter type mismatch
```
Source: fn foo(x: i64) i32 { return x; }
Error: "return type mismatch: expected i32, got i64"
```

### Test 5: Void function no return
```
Source: fn foo() { }
Errors: (none)
```

### Test 6: Void function with value return
```
Source: fn foo() { return 42; }
Error: "return type mismatch: expected void, got i32"
```

---

## What's Next

Let's put everything together into a complete semantic analyzer.

Next: [Lesson 4.8: Putting It Together](../08-putting-together/) →
