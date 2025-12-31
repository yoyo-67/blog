---
title: "5c.2: Bytecode Format"
weight: 2
---

# Lesson 5c.2: Bytecode Format

Designing our instruction set.

---

## Goal

Design a bytecode instruction set that can represent all AIR operations.

---

## Opcode Design

Each instruction has an **opcode** (operation code) - a number that identifies the instruction.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         BYTECODE ENCODING                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Bytecode is a sequence of bytes:                                          │
│                                                                              │
│   [opcode] [operand?] [operand?] [opcode] [operand?] ...                   │
│                                                                              │
│   Examples:                                                                  │
│                                                                              │
│   PUSH_I32 42     →  [0x01] [0x00 0x00 0x00 0x2A]   (1 byte + 4 bytes)     │
│   ADD_I32         →  [0x10]                         (1 byte only)           │
│   LOAD_PARAM 0    →  [0x20] [0x00]                  (1 byte + 1 byte)       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Our Instruction Set

We need instructions for everything AIR can express:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         INSTRUCTION SET                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CONSTANTS:                                                                 │
│   0x01  PUSH_I32 <i32>     Push 32-bit integer onto stack                  │
│   0x02  PUSH_I64 <i64>     Push 64-bit integer onto stack                  │
│   0x03  PUSH_BOOL <u8>     Push boolean (0 or 1)                           │
│                                                                              │
│   ARITHMETIC (all pop 2, push 1):                                           │
│   0x10  ADD_I32            Add two i32 values                              │
│   0x11  SUB_I32            Subtract                                        │
│   0x12  MUL_I32            Multiply                                        │
│   0x13  DIV_I32            Divide                                          │
│   0x14  NEG_I32            Negate (pop 1, push 1)                          │
│   0x18  ADD_I64            64-bit variants                                 │
│   0x19  SUB_I64                                                            │
│   0x1A  MUL_I64                                                            │
│   0x1B  DIV_I64                                                            │
│   0x1C  NEG_I64                                                            │
│                                                                              │
│   VARIABLES:                                                                 │
│   0x20  LOAD_PARAM <u8>    Push parameter N onto stack                     │
│   0x21  LOAD_LOCAL <u8>    Push local variable N onto stack                │
│   0x22  STORE_LOCAL <u8>   Pop into local variable N                       │
│                                                                              │
│   CONTROL FLOW:                                                             │
│   0x30  CALL <u16> <u8>    Call function at index, with N args             │
│   0x31  RET                Return (pop return value)                        │
│   0x32  RET_VOID           Return without value                            │
│                                                                              │
│   OTHER:                                                                     │
│   0x40  POP                Discard top of stack                            │
│   0xFF  HALT               Stop execution                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Opcode Enum

```
Opcode:
    // Constants
    PUSH_I32  = 0x01
    PUSH_I64  = 0x02
    PUSH_BOOL = 0x03

    // Arithmetic i32
    ADD_I32 = 0x10
    SUB_I32 = 0x11
    MUL_I32 = 0x12
    DIV_I32 = 0x13
    NEG_I32 = 0x14

    // Arithmetic i64
    ADD_I64 = 0x18
    SUB_I64 = 0x19
    MUL_I64 = 0x1A
    DIV_I64 = 0x1B
    NEG_I64 = 0x1C

    // Variables
    LOAD_PARAM  = 0x20
    LOAD_LOCAL  = 0x21
    STORE_LOCAL = 0x22

    // Control flow
    CALL     = 0x30
    RET      = 0x31
    RET_VOID = 0x32

    // Other
    POP  = 0x40
    HALT = 0xFF
```

---

## Instruction Encoding

Each instruction has a specific encoding:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      INSTRUCTION ENCODING                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Instruction      Bytes   Format                                           │
│   ─────────────────────────────────────────────────────────                 │
│   PUSH_I32 N       5       [0x01] [N as 4 bytes, little-endian]            │
│   PUSH_I64 N       9       [0x02] [N as 8 bytes, little-endian]            │
│   PUSH_BOOL B      2       [0x03] [0x00 or 0x01]                            │
│                                                                              │
│   ADD_I32          1       [0x10]                                           │
│   SUB_I32          1       [0x11]                                           │
│   (other arith)    1       [opcode]                                         │
│                                                                              │
│   LOAD_PARAM N     2       [0x20] [N as 1 byte]                            │
│   LOAD_LOCAL N     2       [0x21] [N as 1 byte]                            │
│   STORE_LOCAL N    2       [0x22] [N as 1 byte]                            │
│                                                                              │
│   CALL F A         4       [0x30] [F as 2 bytes] [A as 1 byte]             │
│   RET              1       [0x31]                                           │
│   RET_VOID         1       [0x32]                                           │
│                                                                              │
│   POP              1       [0x40]                                           │
│   HALT             1       [0xFF]                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Example Bytecode

Source:
```
fn main() i32 {
    return 3 + 5;
}
```

AIR:
```
%0 = const_i32(3)
%1 = const_i32(5)
%2 = add_i32(%0, %1)
%3 = ret(%2)
```

Bytecode (hex):
```
01 03 00 00 00    ; PUSH_I32 3
01 05 00 00 00    ; PUSH_I32 5
10                ; ADD_I32
31                ; RET
```

Human-readable:
```
PUSH_I32 3
PUSH_I32 5
ADD_I32
RET
```

---

## Program Structure

A complete bytecode program needs:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       PROGRAM STRUCTURE                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Header:                                                                    │
│     magic: "MINI"              4 bytes - identifies file format             │
│     version: 1                 1 byte  - bytecode version                   │
│     num_functions: N           2 bytes - function count                     │
│     entry_point: index         2 bytes - main function index                │
│                                                                              │
│   Function Table:                                                            │
│     For each function:                                                       │
│       name_length: L           1 byte                                       │
│       name: chars              L bytes                                      │
│       num_params: P            1 byte                                       │
│       num_locals: L            1 byte                                       │
│       code_offset: O           4 bytes - where code starts                  │
│       code_length: N           4 bytes - bytes of code                      │
│                                                                              │
│   Code Section:                                                              │
│     All function bodies concatenated                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Bytecode Generator State

```
BytecodeGenerator:
    output: ByteArray           // The bytecode being built
    functions: FunctionTable    // Function metadata
    current_function: index     // Which function we're generating

    // Emit helpers
    emitByte(b)                 // Add single byte
    emitI32(n)                  // Add 4-byte integer
    emitI64(n)                  // Add 8-byte integer
```

---

## Verify Your Understanding

### Question 1
Why do arithmetic instructions have no operands?

Answer: Stack-based VM. The operands are already on the stack. `ADD_I32` pops two values and pushes the result.

### Question 2
Why use different opcodes for i32 and i64 arithmetic?

Answer: The VM needs to know the size of values. `ADD_I32` knows to pop/push 32-bit values, `ADD_I64` for 64-bit.

### Question 3
How many bytes does `PUSH_I32 42` take?

Answer: 5 bytes. 1 byte for opcode (0x01) + 4 bytes for the i32 value.

---

## What's Next

Let's understand how the stack works in detail.

Next: [Lesson 5c.3: Stack Basics](../03-stack-basics/) →
