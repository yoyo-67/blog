---
title: "5.3: Constants"
weight: 3
---

# Lesson 5.3: Generating Constants

Emit code for literal values.

---

## Goal

Generate C code for constant instructions like `const_i32(42)`.

---

## The Pattern

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      CONSTANT GENERATION                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR:                          C Code:                                     │
│                                                                              │
│   %0 = const_i32(42)           int32_t t0 = 42;                            │
│   %3 = const_i64(100)          int64_t t3 = 100;                           │
│   %5 = const_bool(true)        bool t5 = true;                             │
│                                                                              │
│   Pattern: [type] t[index] = [value];                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Temporary Variables

Each AIR instruction result becomes a temporary variable:

```
Instruction index 0 → t0
Instruction index 1 → t1
Instruction index 2 → t2
...
```

This is simple and works because AIR is in SSA form (each value defined once).

---

## Generate Constant

```
function generateConstant(instr, index):
    type_str = typeToCType(instr.type)
    value_str = formatValue(instr.data.value, instr.type)

    emitIndent()
    emit(type_str)
    emit(" t")
    emit(index)
    emit(" = ")
    emit(value_str)
    emitLine(";")
```

---

## Format Value

```
function formatValue(value, type) → string:
    switch type:
        I32, I64:
            return toString(value)
        BOOL:
            return value ? "true" : "false"
```

---

## Example

```
AIR instruction: const_i32(42) at index 0

generateConstant(instr, 0):
    type_str = "int32_t"
    value_str = "42"
    emitIndent() → "    "
    emit("int32_t")
    emit(" t")
    emit("0")
    emit(" = ")
    emit("42")
    emitLine(";")

Output: "    int32_t t0 = 42;"
```

---

## Boolean Constants

```
AIR: const_bool(true) at index 2

Output: "    bool t2 = true;"

AIR: const_bool(false) at index 3

Output: "    bool t3 = false;"
```

---

## Large Numbers

For 64-bit constants, consider suffixes:

```
AIR: const_i64(9223372036854775807)

C code (with suffix):
    int64_t t0 = 9223372036854775807LL;

The LL suffix ensures the literal is treated as long long.
```

```
function formatValue(value, type) → string:
    switch type:
        I32:
            return toString(value)
        I64:
            return toString(value) + "LL"
        BOOL:
            return value ? "true" : "false"
```

---

## Verify Your Implementation

### Test 1: Small i32
```
AIR:    const_i32(42) at index 0
Output: "int32_t t0 = 42;"
```

### Test 2: Zero
```
AIR:    const_i32(0) at index 5
Output: "int32_t t5 = 0;"
```

### Test 3: Negative
```
AIR:    const_i32(-1) at index 2
Output: "int32_t t2 = -1;"
```

### Test 4: i64
```
AIR:    const_i64(100) at index 1
Output: "int64_t t1 = 100LL;"
```

### Test 5: Boolean true
```
AIR:    const_bool(true) at index 3
Output: "bool t3 = true;"
```

### Test 6: Boolean false
```
AIR:    const_bool(false) at index 4
Output: "bool t4 = false;"
```

---

## What's Next

Let's generate binary operations.

Next: [Lesson 5.4: Binary Operations](../04-gen-binary/) →
