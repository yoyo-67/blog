---
title: "5c.4: Generating Constants"
weight: 4
---

# Lesson 5c.4: Generating Constants

Emit PUSH instructions for literal values.

---

## Goal

Generate bytecode for constant instructions like `const_i32(42)`.

---

## The Pattern

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      CONSTANT GENERATION                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR:                          Bytecode:                                   │
│                                                                              │
│   %0 = const_i32(42)           PUSH_I32 42                                 │
│   %3 = const_i64(100)          PUSH_I64 100                                │
│   %5 = const_bool(true)        PUSH_BOOL 1                                 │
│                                                                              │
│   Each constant becomes a PUSH instruction                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Insight: No Temporaries

Unlike C codegen where we create variables like `int32_t t0 = 42;`, bytecode doesn't need names. The value goes directly on the stack.

```
C codegen:      int32_t t0 = 42;    ← creates named variable
Bytecode:       PUSH_I32 42         ← value just sits on stack
```

---

## Generate Constant

```
function generateConstant(instr):
    switch instr.type:
        I32:
            emitByte(PUSH_I32)
            emitI32(instr.value)

        I64:
            emitByte(PUSH_I64)
            emitI64(instr.value)

        BOOL:
            emitByte(PUSH_BOOL)
            emitByte(instr.value ? 1 : 0)
```

---

## Emit Helpers

```
function emitByte(b):
    output.append(b)

function emitI32(n):
    // Little-endian: least significant byte first
    output.append(n & 0xFF)
    output.append((n >> 8) & 0xFF)
    output.append((n >> 16) & 0xFF)
    output.append((n >> 24) & 0xFF)

function emitI64(n):
    // 8 bytes, little-endian
    for i in 0..8:
        output.append((n >> (i * 8)) & 0xFF)
```

---

## Example: PUSH_I32 42

```
generateConstant(const_i32(42)):
    emitByte(0x01)          // PUSH_I32 opcode
    emitI32(42)             // value

Output bytes: [0x01, 0x2A, 0x00, 0x00, 0x00]
              opcode  42 in little-endian

Human readable: PUSH_I32 42
```

---

## Example: PUSH_I32 -1

Negative numbers use two's complement:

```
generateConstant(const_i32(-1)):
    emitByte(0x01)          // PUSH_I32
    emitI32(-1)             // -1 = 0xFFFFFFFF

Output bytes: [0x01, 0xFF, 0xFF, 0xFF, 0xFF]

Human readable: PUSH_I32 -1
```

---

## Example: PUSH_BOOL

```
generateConstant(const_bool(true)):
    emitByte(0x03)          // PUSH_BOOL
    emitByte(1)             // true = 1

Output bytes: [0x03, 0x01]

generateConstant(const_bool(false)):
    emitByte(0x03)          // PUSH_BOOL
    emitByte(0)             // false = 0

Output bytes: [0x03, 0x00]
```

---

## Multiple Constants

```
Source: 3 + 5

AIR:
    %0 = const_i32(3)
    %1 = const_i32(5)
    %2 = add_i32(%0, %1)

Generate constants:

    %0: emitByte(PUSH_I32), emitI32(3)
        → [0x01, 0x03, 0x00, 0x00, 0x00]

    %1: emitByte(PUSH_I32), emitI32(5)
        → [0x01, 0x05, 0x00, 0x00, 0x00]

Combined output:
    [0x01, 0x03, 0x00, 0x00, 0x00, 0x01, 0x05, 0x00, 0x00, 0x00]

Human readable:
    PUSH_I32 3
    PUSH_I32 5
```

---

## Stack Effect

Each PUSH adds one value to the stack:

```
Before PUSH_I32 42:  [...]
After PUSH_I32 42:   [...][42]
                          ↑ new top

Before PUSH_I32 10:  [...][42]
After PUSH_I32 10:   [...][42][10]
                              ↑ new top
```

---

## Verify Your Implementation

### Test 1: Small i32
```
AIR:    const_i32(42)
Bytes:  [0x01, 0x2A, 0x00, 0x00, 0x00]
Human:  PUSH_I32 42
```

### Test 2: Zero
```
AIR:    const_i32(0)
Bytes:  [0x01, 0x00, 0x00, 0x00, 0x00]
Human:  PUSH_I32 0
```

### Test 3: Negative
```
AIR:    const_i32(-1)
Bytes:  [0x01, 0xFF, 0xFF, 0xFF, 0xFF]
Human:  PUSH_I32 -1
```

### Test 4: Boolean true
```
AIR:    const_bool(true)
Bytes:  [0x03, 0x01]
Human:  PUSH_BOOL 1
```

### Test 5: Boolean false
```
AIR:    const_bool(false)
Bytes:  [0x03, 0x00]
Human:  PUSH_BOOL 0
```

### Test 6: i64
```
AIR:    const_i64(100)
Bytes:  [0x02, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
Human:  PUSH_I64 100
```

---

## What's Next

Let's generate arithmetic operations.

Next: [Lesson 5c.5: Generating Arithmetic](../05-gen-arithmetic/) →
