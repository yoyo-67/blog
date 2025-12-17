---
title: "4.2: Type of Expression"
weight: 2
---

# Lesson 4.2: Inferring Expression Types

Determine what type each expression produces.

---

## Goal

Given any expression, determine its type.

---

## Type Inference Rules

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     EXPRESSION TYPE RULES                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Literals:                                                                  │
│     42           → i32                                                       │
│     true/false   → bool                                                      │
│                                                                              │
│   Variables:                                                                │
│     x            → (type of x from declaration)                             │
│                                                                              │
│   Unary:                                                                    │
│     -expr        → (type of expr, must be numeric)                          │
│                                                                              │
│   Binary:                                                                   │
│     a + b        → (type of a, must equal type of b)                        │
│     a - b        → (type of a, must equal type of b)                        │
│     a * b        → (type of a, must equal type of b)                        │
│     a / b        → (type of a, must equal type of b)                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Type Context

To type-check, we need to know variable types. For now, assume we have:

```
TypeContext {
    // Maps variable names to their types
    variables: Map<string, Type>

    // Maps parameter indices to their types
    param_types: Type[]
}
```

We'll build this properly in Lesson 4.3.

---

## Type Inference Function

```
function inferType(zir_instr, context) → Type:
    switch zir_instr.tag:

        CONSTANT:
            return I32   // All constants are i32 for now

        PARAM_REF:
            index = zir_instr.data.param_index
            return context.param_types[index]

        DECL_REF:
            name = zir_instr.data.ref_name
            if name not in context.variables:
                error("Undefined variable: " + name)
                return ERROR
            return context.variables[name]

        NEGATE:
            operand_type = inferType(instructions[zir_instr.data.operand], context)
            return canNegate(operand_type)

        ADD, SUB, MUL, DIV:
            lhs_type = inferType(instructions[zir_instr.data.lhs], context)
            rhs_type = inferType(instructions[zir_instr.data.rhs], context)
            return canBinary(zir_instr.tag, lhs_type, rhs_type)

        DECL:
            value_type = inferType(instructions[zir_instr.data.value], context)
            // Store in context for later use
            context.variables[zir_instr.data.name] = value_type
            return VOID  // Declarations don't produce a value

        RET:
            return inferType(instructions[zir_instr.data.value], context)

        RET_VOID:
            return VOID
```

---

## Binary Operation Type Check

```
function canBinary(op, left_type, right_type) → Type:
    // Propagate errors
    if left_type == ERROR or right_type == ERROR:
        return ERROR

    // Types must match
    if left_type != right_type:
        error("Type mismatch: " + typeName(left_type) +
              " " + opName(op) + " " + typeName(right_type))
        return ERROR

    // Must be numeric
    if left_type != I32 and left_type != I64:
        error("Cannot perform arithmetic on " + typeName(left_type))
        return ERROR

    // Result type equals operand types
    return left_type
```

---

## Example: Type Checking `3 + 5`

```
ZIR:
    %0 = constant(3)
    %1 = constant(5)
    %2 = add(%0, %1)

Type inference:
    %0: constant → I32
    %1: constant → I32
    %2: add(I32, I32) → I32

All types resolved!
```

---

## Example: Type Checking with Variables

```
Source:
    const x: i32 = 5;
    return x + 3;

ZIR:
    %0 = constant(5)
    %1 = decl("x", %0)
    %2 = decl_ref("x")
    %3 = constant(3)
    %4 = add(%2, %3)
    %5 = ret(%4)

Type inference (with context updates):
    %0: constant → I32
    %1: decl("x", %0) → VOID, context.variables["x"] = I32
    %2: decl_ref("x") → context.variables["x"] = I32
    %3: constant → I32
    %4: add(I32, I32) → I32
    %5: ret(I32) → I32

Return type: I32
```

---

## Example: Type Error

```
Source:
    const x: i32 = 5;
    const y: bool = true;
    return x + y;    // Error!

ZIR:
    %0 = constant(5)
    %1 = decl("x", %0)
    %2 = constant(true)
    %3 = decl("y", %2)
    %4 = decl_ref("x")
    %5 = decl_ref("y")
    %6 = add(%4, %5)
    %7 = ret(%6)

Type inference:
    %0: I32
    %1: VOID, context["x"] = I32
    %2: BOOL
    %3: VOID, context["y"] = BOOL
    %4: I32 (from context)
    %5: BOOL (from context)
    %6: add(I32, BOOL) → ERROR: "Type mismatch: i32 + bool"
    %7: ret(ERROR) → ERROR
```

---

## Caching Types

Store computed types to avoid recomputation:

```
function analyzeFunction(fn_zir):
    types = []  // type for each instruction

    for i, instr in enumerate(fn_zir.instructions):
        types[i] = inferType(instr, context, types)

    return types
```

Now `types[i]` gives the type of instruction `%i`.

---

## Verify Your Implementation

### Test 1: Constants
```
Input:  constant(42)
Type:   I32
```

### Test 2: Parameters
```
Function: fn foo(a: i32, b: i64)
Input:  param_ref(0)
Type:   I32

Input:  param_ref(1)
Type:   I64
```

### Test 3: Binary operations
```
Input:  add(constant(3), constant(5))
Type:   I32

Input:  add(param_ref_i32, param_ref_i64)
Type:   ERROR (type mismatch)
```

### Test 4: Variables
```
Input:
    decl("x", constant(5))
    decl_ref("x")
Types:
    decl: VOID (side effect: x = I32)
    decl_ref: I32
```

### Test 5: Undefined variable
```
Input:  decl_ref("undefined")
Type:   ERROR (undefined variable)
```

---

## What's Next

We need a proper symbol table to track all declarations.

Next: [Lesson 4.3: Symbol Table](../03-symbol-table/) →
