---
title: "3.4: Name References"
weight: 4
---

# Lesson 3.4: Variable Declarations and References

Handle `const x = ...` and using `x` later.

---

## Goal

Generate ZIR for variable declarations and references to declared variables.

---

## Two Instructions

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     DECLARATION AND REFERENCE                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   DECL: Create a named binding                                              │
│                                                                              │
│     const x: i32 = 42;                                                      │
│     → %0 = constant(42)                                                     │
│     → %1 = decl("x", %0)                                                    │
│                                                                              │
│   DECL_REF: Use a named binding                                             │
│                                                                              │
│     return x;                                                               │
│     → %2 = decl_ref("x")                                                    │
│     → %3 = ret(%2)                                                          │
│                                                                              │
│   Names are STRINGS in ZIR. Actual resolution happens in Sema.             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Generate Variable Declaration

```
function generateVarDecl(stmt):
    // Generate the initial value first
    value_ref = generateExpr(stmt.value)

    // Then emit the declaration
    emit(Decl {
        name: stmt.name,
        value: value_ref
    })
```

---

## Generate Identifier Reference

Already in generateExpr:

```
function generateExpr(expr) → InstrRef:
    switch expr.type:
        // ... other cases ...

        IdentifierExpr:
            return emit(DeclRef { name: expr.name })
```

---

## Full Example

```
Source:
const x: i32 = 5;
const y: i32 = x + 3;
return y;

AST:
    VarDecl { name: "x", value: NumberExpr(5) }
    VarDecl { name: "y", value: BinaryExpr(Identifier("x"), +, NumberExpr(3)) }
    ReturnStmt { value: IdentifierExpr("y") }

ZIR Generation:

Statement 1: const x: i32 = 5;
    generateVarDecl():
        value_ref = generateExpr(NumberExpr(5)):
            emit(Constant { value: 5 }) → 0
        emit(Decl { name: "x", value: 0 }) → 1

Statement 2: const y: i32 = x + 3;
    generateVarDecl():
        value_ref = generateExpr(BinaryExpr(x, +, 3)):
            lhs = generateExpr(IdentifierExpr("x")):
                emit(DeclRef { name: "x" }) → 2
            rhs = generateExpr(NumberExpr(3)):
                emit(Constant { value: 3 }) → 3
            emit(Add { lhs: 2, rhs: 3 }) → 4
        emit(Decl { name: "y", value: 4 }) → 5

Statement 3: return y;
    generateReturn():
        value = generateExpr(IdentifierExpr("y")):
            emit(DeclRef { name: "y" }) → 6
        emit(Ret { value: 6 }) → 7

Final ZIR:
    %0 = constant(5)
    %1 = decl("x", %0)
    %2 = decl_ref("x")
    %3 = constant(3)
    %4 = add(%2, %3)
    %5 = decl("y", %4)
    %6 = decl_ref("y")
    %7 = ret(%6)
```

---

## Why Strings?

Why store names as strings instead of resolving them now?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      WHY UNRESOLVED NAMES?                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. ZIR is UNTYPED - we don't do semantic analysis yet                     │
│                                                                              │
│   2. Simpler code - ZIR generator just records what it sees                 │
│                                                                              │
│   3. Error reporting - Sema can report "undefined variable x" later        │
│                                                                              │
│   4. Forward references - Some languages allow using names before           │
│      they're declared. Deferring resolution handles this.                   │
│                                                                              │
│   Sema will resolve decl_ref("x") to an actual memory location.            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Generate Statement

```
function generateStatement(stmt):
    switch stmt.type:
        VarDecl:
            generateVarDecl(stmt)

        ReturnStmt:
            if stmt.value != null:
                value = generateExpr(stmt.value)
                emit(Ret { value: value })
            else:
                emit(RetVoid {})

        Block:
            for s in stmt.statements:
                generateStatement(s)
```

---

## Verify Your Implementation

### Test 1: Simple declaration
```
Input:  const x: i32 = 42;
ZIR:
    %0 = constant(42)
    %1 = decl("x", %0)
```

### Test 2: Declaration with expression
```
Input:  const sum: i32 = 3 + 5;
ZIR:
    %0 = constant(3)
    %1 = constant(5)
    %2 = add(%0, %1)
    %3 = decl("sum", %2)
```

### Test 3: Reference declared variable
```
Input:
    const x: i32 = 10;
    return x;
ZIR:
    %0 = constant(10)
    %1 = decl("x", %0)
    %2 = decl_ref("x")
    %3 = ret(%2)
```

### Test 4: Multiple declarations
```
Input:
    const a: i32 = 1;
    const b: i32 = 2;
    return a + b;
ZIR:
    %0 = constant(1)
    %1 = decl("a", %0)
    %2 = constant(2)
    %3 = decl("b", %2)
    %4 = decl_ref("a")
    %5 = decl_ref("b")
    %6 = add(%4, %5)
    %7 = ret(%6)
```

### Test 5: Use in expression
```
Input:
    const x: i32 = 5;
    const y: i32 = x * 2;
ZIR:
    %0 = constant(5)
    %1 = decl("x", %0)
    %2 = decl_ref("x")
    %3 = constant(2)
    %4 = mul(%2, %3)
    %5 = decl("y", %4)
```

---

## Note: Undefined Variables

At this stage, we don't check if variables exist:

```
Input:  return undefined_var;
ZIR:    %0 = decl_ref("undefined_var")
        %1 = ret(%0)

This is valid ZIR! Sema will catch the error.
```

---

## What's Next

Let's handle function parameters, which are like variables but come from the function signature.

Next: [Lesson 3.5: Parameter References](../05-param-references/) →
