---
title: "4.1: Type System"
weight: 1
---

# Lesson 4.1: Defining Types

Before type checking, we need to define what types exist.

---

## Goal

Define the type system for our mini language.

---

## Our Types

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           TYPE SYSTEM                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Primitive Types:                                                          │
│                                                                              │
│   i32   - 32-bit signed integer                                             │
│   i64   - 64-bit signed integer                                             │
│   bool  - boolean (true/false)                                              │
│   void  - no value (for functions that don't return)                        │
│                                                                              │
│   That's it for our mini compiler!                                          │
│                                                                              │
│   Real languages have: floats, strings, arrays, structs, pointers, etc.     │
│   We'll keep it simple.                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Type Representation

```
enum Type {
    I32,
    I64,
    BOOL,
    VOID,
    ERROR,    // For type errors - allows continued analysis
}
```

The ERROR type is special - it represents "we don't know" when errors occur. This prevents cascading error messages.

---

## Type Properties

```
function typeSize(type) → integer:
    switch type:
        I32:   return 4    // 4 bytes
        I64:   return 8    // 8 bytes
        BOOL:  return 1    // 1 byte
        VOID:  return 0    // No storage
        ERROR: return 0

function typeName(type) → string:
    switch type:
        I32:   return "i32"
        I64:   return "i64"
        BOOL:  return "bool"
        VOID:  return "void"
        ERROR: return "<error>"
```

---

## Converting AST Types

The parser produces TypeExpr with string names. Convert to actual types:

```
function resolveType(type_expr) → Type:
    switch type_expr.name:
        "i32":  return I32
        "i64":  return I64
        "bool": return BOOL
        "void": return VOID
        default:
            error("Unknown type: " + type_expr.name)
            return ERROR
```

---

## Type Compatibility

Which types can be used together?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      TYPE COMPATIBILITY                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Arithmetic (+, -, *, /):                                                  │
│     i32 ○ i32 → i32    ✓                                                    │
│     i64 ○ i64 → i64    ✓                                                    │
│     i32 ○ i64 → ???    ✗ (we'll require explicit casts)                    │
│     bool ○ i32 → ???   ✗ (not allowed)                                      │
│                                                                              │
│   Comparison (==, <, >):                                                    │
│     i32 == i32 → bool  ✓                                                    │
│                                                                              │
│   Negation (-):                                                             │
│     -i32 → i32         ✓                                                    │
│     -bool → ???        ✗ (not allowed)                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Type Checking Rules

```
function canAdd(left_type, right_type) → Type:
    if left_type == ERROR or right_type == ERROR:
        return ERROR   // Don't cascade errors

    if left_type == I32 and right_type == I32:
        return I32

    if left_type == I64 and right_type == I64:
        return I64

    error("Cannot add " + typeName(left_type) + " and " + typeName(right_type))
    return ERROR

function canNegate(type) → Type:
    if type == ERROR:
        return ERROR

    if type == I32:
        return I32

    if type == I64:
        return I64

    error("Cannot negate " + typeName(type))
    return ERROR
```

---

## Numeric Literals

What type is the number `42`?

Options:
1. **Always i32**: Simple, but `42` can't be used where i64 is expected
2. **Context-dependent**: Infer from usage (complex)
3. **Default with suffix**: `42` is i32, `42L` is i64

We'll use option 1 (always i32) for simplicity.

```
function typeOfNumber(value) → Type:
    return I32   // All integer literals are i32
```

---

## Verify Your Implementation

### Test 1: Type resolution
```
resolveType(TypeExpr { name: "i32" }) → I32
resolveType(TypeExpr { name: "void" }) → VOID
resolveType(TypeExpr { name: "unknown" }) → ERROR + error message
```

### Test 2: Arithmetic compatibility
```
canAdd(I32, I32) → I32
canAdd(I64, I64) → I64
canAdd(I32, I64) → ERROR + error message
canAdd(I32, BOOL) → ERROR + error message
```

### Test 3: Negation
```
canNegate(I32) → I32
canNegate(I64) → I64
canNegate(BOOL) → ERROR + error message
```

### Test 4: Type properties
```
typeSize(I32) → 4
typeSize(I64) → 8
typeName(I32) → "i32"
```

---

## Type in AIR Instructions

AIR instructions will carry type information:

```
// ZIR (untyped)
Add { lhs: 0, rhs: 1 }

// AIR (typed)
AddI32 { lhs: 0, rhs: 1, result_type: I32 }
// or
AddI64 { lhs: 0, rhs: 1, result_type: I64 }
```

---

## What's Next

Let's figure out the type of arbitrary expressions.

Next: [Lesson 4.2: Type of Expression](../02-type-of-expr/) →
