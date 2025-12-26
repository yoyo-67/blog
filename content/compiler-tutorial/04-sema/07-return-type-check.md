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

## Implementing Inferred Return Types

To infer the return type, we need a variable to track what we've seen:

```
function analyzeFunction(func):
    errors = []
    names = {}
    inst_types = []
    inferred_return_type = null    // ← Track inferred type

    // ... process instructions ...

    for i in 0..instruction_count:
        inst = instruction_at(i)

        result_type = switch inst:
            // ... other cases ...

            return_stmt(r):
                actual_type = inst_types[r.value]

                if func.return_type != null:
                    // Declared type: check against it
                    if actual_type != func.return_type:
                        errors.append(return_type_mismatch)
                else:
                    // No declared type: infer it
                    if inferred_return_type == null:
                        // First return: set the inferred type
                        inferred_return_type = actual_type
                    else:
                        // Subsequent returns: must match inferred
                        if actual_type != inferred_return_type:
                            errors.append(conflicting_return_types)

                null

    // Store the inferred type back to the function
    if func.return_type == null and inferred_return_type != null:
        func.return_type = inferred_return_type
```

---

## Why Infer Return Types?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      WHY INFER RETURN TYPES?                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. Less Boilerplate                                                        │
│      fn add(a: i32, b: i32) { return a + b; }   // Type is obvious          │
│                                                                              │
│   2. Consistency with Modern Languages                                       │
│      Rust, Zig, Swift all support return type inference                      │
│                                                                              │
│   3. Type Safety Still Maintained                                            │
│      The compiler knows the type, even if not written                        │
│                                                                              │
│   4. Codegen Still Works                                                     │
│      func.return_type is populated after sema                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

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

## Multiple Returns with Inferred Types

When inferring types, all return statements must agree:

```
fn mystery(x: i32) {
    if x > 0:
        return 42;       // First return: infers i32
    return true;         // Second return: bool ≠ i32, ERROR!
}
```

The algorithm:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     INFERRED TYPE WITH MULTIPLE RETURNS                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   First return encountered:                                                  │
│       inferred_type = actual_type                                            │
│                                                                              │
│   Each subsequent return:                                                    │
│       if actual_type ≠ inferred_type:                                        │
│           ERROR: conflicting return types                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Supporting Multiple Return Types (Union Types)

What if you **want** to allow different return types? Some languages support this:

```
// TypeScript-style union types
fn getValue(useString: bool) i32 | string {
    if useString:
        return "hello";
    return 42;
}
```

### Option 1: Tagged Unions (Recommended)

Create an explicit union type:

```
type Result = union {
    int_val: i32,
    str_val: string,
}

fn getValue(useString: bool) Result {
    if useString:
        return Result { str_val: "hello" };
    return Result { int_val: 42 };
}
```

This is explicit and type-safe.

### Option 2: Implicit Union Types

Track all return types and create a union:

```
function analyzeFunction(func):
    return_types = []    // Track ALL return types

    for inst in instructions:
        if inst is return_stmt:
            actual_type = inst_types[inst.value]
            if actual_type not in return_types:
                return_types.append(actual_type)

    if return_types.length == 1:
        func.return_type = return_types[0]
    else:
        // Multiple different types returned
        func.return_type = UnionType(return_types)
```

### Option 3: Least Upper Bound (LUB)

Find a common supertype:

```
fn foo(x: bool) {
    if x:
        return 42;       // i32
    return 100;          // i32
}
// Both are i32, so return type = i32

fn bar(x: bool) {
    if x:
        return 42;       // i32
    return 42.0;         // f64
}
// LUB(i32, f64) = f64 (numbers)
// or error if no common type
```

Implementation:
```
function findLUB(type1, type2):
    if type1 == type2:
        return type1

    // Define type hierarchy
    if isNumeric(type1) and isNumeric(type2):
        return largerNumericType(type1, type2)

    // No common type
    return null  // or error
```

---

## Comparison of Approaches

```
┌────────────────────┬──────────────────────────────────────────────────────────┐
│ Approach           │ Trade-offs                                               │
├────────────────────┼──────────────────────────────────────────────────────────┤
│ Strict (one type)  │ Simple, predictable, catches errors                      │
│                    │ Requires explicit unions if needed                       │
├────────────────────┼──────────────────────────────────────────────────────────┤
│ Tagged Unions      │ Type-safe, explicit intent                               │
│                    │ More verbose, needs union type support                   │
├────────────────────┼──────────────────────────────────────────────────────────┤
│ Implicit Unions    │ Flexible, less boilerplate                               │
│                    │ Complex codegen, harder to reason about                  │
├────────────────────┼──────────────────────────────────────────────────────────┤
│ LUB                │ Intuitive for numeric types                              │
│                    │ Can lose precision, surprising behavior                  │
└────────────────────┴──────────────────────────────────────────────────────────┘
```

**Recommendation**: Start with strict single-type inference. Add explicit tagged unions if needed. This matches languages like Rust, Zig, and Go.

---

## Complete Sema with Inference

```
function analyzeFunction(func):
    errors = []
    names = {}
    inst_types = []
    inferred_return_type = null

    // Register parameters
    for param in func.params:
        names.put(param.name, param.type)

    for i in 0..instruction_count:
        inst = instruction_at(i)

        result_type = switch inst:
            constant(c):
                inferConstantType(c)    // "i32", "bool", etc.

            param_ref(idx):
                func.params[idx].type

            decl(d):
                // ... handle declaration ...

            decl_ref(d):
                // ... handle reference ...

            add(lhs, rhs):
                // Track binary op result type
                lhs_type = inst_types[lhs]
                rhs_type = inst_types[rhs]
                if lhs_type == rhs_type:
                    lhs_type
                else:
                    null

            return_stmt(r):
                actual_type = if r.value != null:
                    inst_types[r.value]
                else:
                    "void"

                expected_type = func.return_type

                if expected_type != null:
                    // Explicit return type: check it
                    if actual_type != expected_type:
                        errors.append(return_type_mismatch {
                            expected: expected_type,
                            actual: actual_type,
                            inst: inst
                        })
                else:
                    // No declared type: infer
                    if inferred_return_type == null:
                        inferred_return_type = actual_type
                    else if actual_type != inferred_return_type:
                        errors.append(conflicting_return_types {
                            first: inferred_return_type,
                            second: actual_type,
                            inst: inst
                        })

                null    // return has no result type

        inst_types.append(result_type)

    // Store inferred type
    if func.return_type == null:
        func.return_type = inferred_return_type or "void"

    return errors
```

---

## New Error Type

Add error for conflicting inferred types:

```
Error = union {
    // ... existing errors ...

    conflicting_return_types: struct {
        first: []const u8,     // Type from first return
        second: []const u8,    // Conflicting type
        inst: *const Instruction,
    },
}

function getMessage(error):
    switch error:
        conflicting_return_types:
            return "conflicting return types: first return is {first}, but this return is {second}"
```

---

## Verify Your Implementation

### Test 1: Single return inference
```
Source: fn foo(x: i32) { return x; }
Result: func.return_type = "i32"
Errors: (none)
```

### Test 2: Multiple matching returns
```
Source: fn abs(n: i32) { if n < 0: return -n; return n; }
Result: func.return_type = "i32"
Errors: (none)
```

### Test 3: Conflicting return types
```
Source: fn bad(x: bool) { if x: return 42; return true; }
Error: "conflicting return types: first return is i32, but this return is bool"
```

### Test 4: No return statements
```
Source: fn foo() { }
Result: func.return_type = "void"
Errors: (none)
```

### Test 5: Void with explicit return
```
Source: fn foo() { return; }
Result: func.return_type = "void"
Errors: (none)
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
