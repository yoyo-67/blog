---
title: "3.1: IR Instructions"
weight: 1
---

# Lesson 3.1: IR Instruction Types

Before generating IR, we define what instructions look like.

---

## Goal

Define the data structures for ZIR instructions.

---

## What Is an Instruction?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          IR INSTRUCTION                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   %2 = add(%0, %1)                                                          │
│    ↑    ↑    ↑   ↑                                                          │
│    │    │    │   └── Second operand (reference to %1)                       │
│    │    │    └── First operand (reference to %0)                            │
│    │    └── Operation (add)                                                 │
│    └── Result index (this is instruction #2)                                │
│                                                                              │
│   Every instruction:                                                        │
│   - Has an index (%N)                                                       │
│   - Has an operation tag                                                    │
│   - May have operands (references to other instructions)                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Instruction Set

For our mini compiler:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         ZIR INSTRUCTIONS                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CONSTANTS:                                                                 │
│     constant(value)         Load an integer constant                        │
│                                                                              │
│   ARITHMETIC:                                                                │
│     add(lhs, rhs)           Addition                                        │
│     sub(lhs, rhs)           Subtraction                                     │
│     mul(lhs, rhs)           Multiplication                                  │
│     div(lhs, rhs)           Division                                        │
│     negate(operand)         Unary negation                                  │
│                                                                              │
│   VARIABLES:                                                                │
│     decl(name, value)       Declare variable with initial value            │
│     decl_ref(name)          Reference a declared variable                   │
│     param_ref(index)        Reference a function parameter                  │
│                                                                              │
│   CONTROL:                                                                  │
│     ret(value)              Return from function                            │
│     ret_void()              Return without value                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Structures

### Instruction Index

```
// Reference to another instruction's result
InstrRef = integer    // Index into instruction list
```

### Instruction Tags

```
enum InstrTag {
    CONSTANT,
    ADD,
    SUB,
    MUL,
    DIV,
    NEGATE,
    DECL,
    DECL_REF,
    PARAM_REF,
    RET,
    RET_VOID,
}
```

### Instruction Data

```
Instruction {
    tag: InstrTag,
    data: InstrData
}

// Each tag has different data:
InstrData = {
    // CONSTANT
    constant_value: integer,

    // ADD, SUB, MUL, DIV
    binary_lhs: InstrRef,
    binary_rhs: InstrRef,

    // NEGATE
    unary_operand: InstrRef,

    // DECL
    decl_name: string,
    decl_value: InstrRef,

    // DECL_REF
    ref_name: string,

    // PARAM_REF
    param_index: integer,

    // RET
    ret_value: InstrRef,

    // RET_VOID has no data
}
```

---

## Alternative: Tagged Union

Many languages express this as a tagged union:

```
Instruction =
    | Constant { value: integer }
    | Add { lhs: InstrRef, rhs: InstrRef }
    | Sub { lhs: InstrRef, rhs: InstrRef }
    | Mul { lhs: InstrRef, rhs: InstrRef }
    | Div { lhs: InstrRef, rhs: InstrRef }
    | Negate { operand: InstrRef }
    | Decl { name: string, value: InstrRef }
    | DeclRef { name: string }
    | ParamRef { index: integer }
    | Ret { value: InstrRef }
    | RetVoid
```

---

## Function ZIR

A function's ZIR contains:

```
FunctionZIR {
    name: string,
    params: Parameter[],
    return_type: TypeExpr,
    instructions: Instruction[]
}
```

---

## Example

```
Source: const x: i32 = 3 + 5;

Instructions:
  [0] Constant { value: 3 }
  [1] Constant { value: 5 }
  [2] Add { lhs: 0, rhs: 1 }
  [3] Decl { name: "x", value: 2 }

Written as:
  %0 = constant(3)
  %1 = constant(5)
  %2 = add(%0, %1)
  %3 = decl("x", %2)
```

---

## Instruction Ordering

Instructions can only reference earlier instructions:

```
%0 = constant(3)
%1 = add(%0, %2)     // ERROR! %2 doesn't exist yet
%2 = constant(5)
```

This is called **Single Static Assignment (SSA)** form - each value is defined exactly once.

---

## Verify Your Implementation

Create instructions manually and verify they can represent:

### Test 1: Constant
```
Expression: 42
Instructions: [Constant { value: 42 }]
Text: %0 = constant(42)
```

### Test 2: Addition
```
Expression: 3 + 5
Instructions:
    [0] Constant { value: 3 }
    [1] Constant { value: 5 }
    [2] Add { lhs: 0, rhs: 1 }
Text:
    %0 = constant(3)
    %1 = constant(5)
    %2 = add(%0, %1)
```

### Test 3: Variable
```
Statement: const x: i32 = 42;
Instructions:
    [0] Constant { value: 42 }
    [1] Decl { name: "x", value: 0 }
Text:
    %0 = constant(42)
    %1 = decl("x", %0)
```

### Test 4: Reference
```
Expression: x (where x was declared earlier)
Instructions: [DeclRef { name: "x" }]
Text: %0 = decl_ref("x")
```

---

## What's Next

Let's generate these instructions from AST expressions.

Next: [Lesson 3.2: Flatten Expressions](../02-flatten-expr/) →
