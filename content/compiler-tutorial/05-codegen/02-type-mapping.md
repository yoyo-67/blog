---
title: "5.2: Type Mapping"
weight: 2
---

# Lesson 5.2: Mapping Types to C

Convert our types to C equivalents.

---

## Goal

Map i32, i64, bool, void to C types.

---

## Type Mapping Table

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         TYPE MAPPING                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Our Type        C Type              Header                                │
│   ────────        ──────              ──────                                │
│   i32             int32_t             <stdint.h>                            │
│   i64             int64_t             <stdint.h>                            │
│   bool            bool                <stdbool.h>                           │
│   void            void                (built-in)                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Fixed-Width Types?

We use `int32_t` instead of `int` because:

```
int  → Size varies by platform (16, 32, or 64 bits)
int32_t → Always 32 bits, guaranteed

Our language specifies exact sizes, so we need exact C types.
```

---

## Type to C String

```
function typeToCType(type) → string:
    switch type:
        I32:   return "int32_t"
        I64:   return "int64_t"
        BOOL:  return "bool"
        VOID:  return "void"
        ERROR: return "/* error */"
```

---

## Required Headers

Generate at the top of output:

```c
#include <stdint.h>   // int32_t, int64_t
#include <stdbool.h>  // bool, true, false
```

---

## Example Mappings

### Function Signatures

```
Our language:
fn add(a: i32, b: i32) i32

C code:
int32_t add(int32_t p0, int32_t p1)
```

### Variable Declarations

```
Our language:
const x: i32 = 42;

C code:
int32_t local_0 = 42;
```

### Return Types

```
Our language:
fn doSomething() void

C code:
void doSomething()
```

---

## Code Generator Helper

```
CodeGenerator {
    // Type conversion
    function emitType(type):
        emit(typeToCType(type))
}

// Usage
emitType(I32)     // emits: "int32_t"
emitType(VOID)    // emits: "void"
```

---

## Type in Declarations

```
function emitVarDecl(name, type, value):
    emitIndent()
    emitType(type)
    emit(" ")
    emit(name)
    emit(" = ")
    emit(value)
    emitLine(";")

// emitVarDecl("t0", I32, "42")
// Output: "    int32_t t0 = 42;"
```

---

## Verify Your Implementation

### Test 1: i32 mapping
```
typeToCType(I32) → "int32_t"
```

### Test 2: i64 mapping
```
typeToCType(I64) → "int64_t"
```

### Test 3: bool mapping
```
typeToCType(BOOL) → "bool"
```

### Test 4: void mapping
```
typeToCType(VOID) → "void"
```

### Test 5: Variable declaration
```
emitVarDecl("t0", I32, "42")
Output: "int32_t t0 = 42;"
```

### Test 6: Function signature
```
Function: fn foo(x: i32) i64
Output: "int64_t foo(int32_t p0)"
```

---

## What's Next

Let's generate code for constants.

Next: [Lesson 5.3: Constants](../03-gen-constants/) →
