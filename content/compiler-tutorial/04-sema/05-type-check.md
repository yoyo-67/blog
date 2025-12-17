---
title: "4.5: Type Check"
weight: 5
---

# Lesson 4.5: Type Checking

Verify that types are used correctly throughout the program.

---

## Goal

Ensure all operations have compatible types and catch type errors.

---

## Type Checking Points

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      WHERE TO TYPE CHECK                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. BINARY OPERATIONS                                                      │
│      a + b   → Both operands must have same numeric type                   │
│                                                                              │
│   2. UNARY OPERATIONS                                                       │
│      -x      → Operand must be numeric                                      │
│                                                                              │
│   3. VARIABLE DECLARATIONS                                                  │
│      const x: i32 = expr   → expr must have type i32                       │
│                                                                              │
│   4. RETURN STATEMENTS                                                      │
│      return expr   → expr type must match function return type             │
│                                                                              │
│   5. FUNCTION CALLS (if we had them)                                       │
│      foo(a, b)   → argument types must match parameter types               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Type Check: Binary Operations

```
function checkBinaryOp(op, lhs_type, rhs_type) → Type:
    // Propagate errors
    if lhs_type == ERROR or rhs_type == ERROR:
        return ERROR

    // Types must match
    if lhs_type != rhs_type:
        error("Type mismatch in " + opName(op) + ": " +
              typeName(lhs_type) + " vs " + typeName(rhs_type))
        return ERROR

    // Must be numeric
    if not isNumeric(lhs_type):
        error("Cannot perform " + opName(op) + " on " + typeName(lhs_type))
        return ERROR

    return lhs_type

function isNumeric(type) → boolean:
    return type == I32 or type == I64
```

---

## Type Check: Unary Operations

```
function checkUnaryOp(op, operand_type) → Type:
    if operand_type == ERROR:
        return ERROR

    switch op:
        NEGATE:
            if not isNumeric(operand_type):
                error("Cannot negate " + typeName(operand_type))
                return ERROR
            return operand_type
```

---

## Type Check: Variable Declaration

When the AST has an explicit type annotation:

```
const x: i32 = some_expression;
```

We need to verify the expression type matches:

```
function checkVarDecl(declared_type, value_type) → Type:
    if value_type == ERROR:
        return ERROR

    if declared_type != value_type:
        error("Cannot assign " + typeName(value_type) +
              " to variable of type " + typeName(declared_type))
        return ERROR

    return declared_type
```

---

## Type Check: Return Statement

```
function checkReturn(return_type, expected_type):
    if return_type == ERROR:
        return  // Already reported

    if return_type != expected_type:
        error("Return type mismatch: expected " + typeName(expected_type) +
              ", got " + typeName(return_type))
```

---

## Integrating Type Checks

```
function analyzeInstruction(zir_instr, context):
    switch zir_instr.tag:

        ADD, SUB, MUL, DIV:
            lhs_type = type_of[zir_instr.data.lhs]
            rhs_type = type_of[zir_instr.data.rhs]
            result_type = checkBinaryOp(zir_instr.tag, lhs_type, rhs_type)
            return { type: result_type, ... }

        NEGATE:
            operand_type = type_of[zir_instr.data.operand]
            result_type = checkUnaryOp(NEGATE, operand_type)
            return { type: result_type, ... }

        DECL:
            value_type = type_of[zir_instr.data.value]
            // If AST has declared type:
            if declared_type != null:
                checkVarDecl(declared_type, value_type)
            // ... continue with declaration

        RET:
            value_type = type_of[zir_instr.data.value]
            checkReturn(value_type, function_return_type)
            return { type: value_type, ... }
```

---

## Example: Type Mismatch

```
Source:
fn foo(a: i32, b: i64) i32 {
    return a + b;
}

Analysis:
    %0 = param_ref(0)  → type: I32
    %1 = param_ref(1)  → type: I64
    %2 = add(%0, %1)   → checkBinaryOp(ADD, I32, I64)
                       → Error: "Type mismatch in +: i32 vs i64"
                       → type: ERROR
    %3 = ret(%2)       → type: ERROR (no additional error)
```

---

## Example: Return Type Mismatch

```
Source:
fn foo() i32 {
    return;    // Void return in i32 function!
}

Analysis:
    %0 = ret_void()  → checkReturn(VOID, I32)
                     → Error: "Return type mismatch: expected i32, got void"
```

---

## Example: Wrong Type Assigned

```
Source:
fn foo() i32 {
    const x: i32 = true;   // Assigning bool to i32!
    return x;
}

Analysis:
    %0 = constant(true)  → type: BOOL
    %1 = decl("x", %0)   → declared type: I32, value type: BOOL
                         → Error: "Cannot assign bool to variable of type i32"
```

---

## Error Recovery

Don't stop at the first error. Use ERROR type to continue:

```
const x: i32 = true;     // Error 1: type mismatch
const y: i32 = x + 1;    // x has ERROR type, but we can still analyze
return y;                 // Continue checking return
```

By propagating ERROR, we avoid cascading messages like "undefined variable x" when the real problem was the type mismatch.

---

## Verify Your Implementation

### Test 1: Valid binary operation
```
Input:  add(constant(3), constant(5))
Types:  I32, I32
Result: I32 (no error)
```

### Test 2: Type mismatch in binary
```
Input:  add(param_ref_i32, param_ref_i64)
Types:  I32, I64
Result: ERROR + "Type mismatch in +: i32 vs i64"
```

### Test 3: Non-numeric binary
```
Input:  add(constant_bool, constant_bool)
Types:  BOOL, BOOL
Result: ERROR + "Cannot perform + on bool"
```

### Test 4: Return type mismatch
```
Function return type: i64
Return value type: i32
Result: Error "Return type mismatch: expected i64, got i32"
```

### Test 5: Void return in non-void function
```
Function return type: i32
Return: ret_void()
Result: Error "Return type mismatch: expected i32, got void"
```

### Test 6: Valid void return
```
Function return type: void
Return: ret_void()
Result: No error
```

---

## What's Next

Let's generate the typed AIR output.

Next: [Lesson 4.6: AIR Output](../06-air-output/) →
