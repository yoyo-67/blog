---
title: "5c.3: Stack Basics"
weight: 3
---

# Lesson 5c.3: Stack Basics

Understanding the execution stack.

---

## Goal

Understand how a stack-based VM uses the stack for all operations.

---

## The Stack

A stack is a last-in, first-out (LIFO) data structure:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            THE STACK                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Operations:                                                                │
│                                                                              │
│   push(value)  - Add value to top                                           │
│   pop()        - Remove and return top value                                │
│   peek()       - Look at top without removing                               │
│                                                                              │
│   Example:                                                                   │
│                                                                              │
│   push(3)     push(5)     push(7)     pop()       pop()                    │
│                                                                              │
│      │           │          [7]         │           │                       │
│      │          [5]         [5]        [5]          │                       │
│     [3]         [3]         [3]        [3]         [3]                      │
│   ───────     ───────     ───────    ───────     ───────                    │
│                                       → 7         → 5                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stack Pointer

The **stack pointer (SP)** tracks the top of the stack:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         STACK POINTER                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Stack array:  [  3  ][  5  ][  7  ][    ][    ][    ][    ]               │
│                    0      1      2     3     4     5     6                  │
│                                        ↑                                    │
│                                       SP = 3 (next free slot)               │
│                                                                              │
│   push(x):                                                                   │
│       stack[SP] = x                                                         │
│       SP = SP + 1                                                           │
│                                                                              │
│   pop():                                                                     │
│       SP = SP - 1                                                           │
│       return stack[SP]                                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## How Operations Use the Stack

Every operation works by manipulating the stack:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      OPERATIONS AND THE STACK                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   PUSH_I32 42:                                                              │
│       Before: [...]           After: [...][42]                              │
│       Pushes constant onto stack                                            │
│                                                                              │
│   ADD_I32:                                                                   │
│       Before: [...][3][5]     After: [...][8]                               │
│       Pops two, pushes sum                                                  │
│                                                                              │
│   NEG_I32:                                                                   │
│       Before: [...][5]        After: [...][-5]                              │
│       Pops one, pushes negated                                              │
│                                                                              │
│   POP:                                                                       │
│       Before: [...][5]        After: [...]                                  │
│       Discards top value                                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Trace: 3 + 5

Let's trace `3 + 5`:

```
Bytecode:
    PUSH_I32 3
    PUSH_I32 5
    ADD_I32

Execution:

Step 1: PUSH_I32 3
    Stack: [3]
           SP=1

Step 2: PUSH_I32 5
    Stack: [3][5]
              SP=2

Step 3: ADD_I32
    Pop 5, pop 3, compute 3+5=8, push 8
    Stack: [8]
           SP=1

Result: 8 is on top of stack
```

---

## Trace: (2 + 3) * 4

More complex: `(2 + 3) * 4`

```
Bytecode:
    PUSH_I32 2
    PUSH_I32 3
    ADD_I32
    PUSH_I32 4
    MUL_I32

Execution:

Step 1: PUSH_I32 2
    Stack: [2]

Step 2: PUSH_I32 3
    Stack: [2][3]

Step 3: ADD_I32
    Stack: [5]       ← 2+3

Step 4: PUSH_I32 4
    Stack: [5][4]

Step 5: MUL_I32
    Stack: [20]      ← 5*4

Result: 20
```

---

## Order Matters

For non-commutative operations, order matters:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        OPERAND ORDER                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   For subtraction:  a - b                                                   │
│                                                                              │
│   We want:          PUSH a                                                  │
│                     PUSH b                                                  │
│                     SUB                                                     │
│                                                                              │
│   SUB pops b first, then a, computes a - b                                 │
│                                                                              │
│   Stack before SUB:  [...][a][b]                                           │
│                               ↑ top                                         │
│                                                                              │
│   pop() → b                                                                 │
│   pop() → a                                                                 │
│   push(a - b)                                                               │
│                                                                              │
│   Example: 10 - 3                                                           │
│   PUSH_I32 10    Stack: [10]                                               │
│   PUSH_I32 3     Stack: [10][3]                                            │
│   SUB_I32        Stack: [7]     ← 10 - 3, not 3 - 10                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stack State During Function

Inside a function, the stack holds:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       FUNCTION STACK LAYOUT                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   function add(a: i32, b: i32) i32 {                                        │
│       const x = a + b;                                                      │
│       return x;                                                             │
│   }                                                                          │
│                                                                              │
│   Stack layout:                                                              │
│                                                                              │
│   [caller's values...][a][b][x][temporaries...]                             │
│                        ↑     ↑  ↑                                           │
│                      params  locals  working space                          │
│                                                                              │
│   The VM tracks where params/locals start (base pointer)                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stack Machine Properties

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STACK MACHINE PROPERTIES                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Advantages:                                                                │
│   • Simple instruction encoding (no register fields)                        │
│   • Easy code generation (just push operands, emit op)                      │
│   • Naturally handles expression nesting                                    │
│                                                                              │
│   Disadvantages:                                                             │
│   • More instructions (push every operand)                                  │
│   • Memory traffic (stack in RAM, not registers)                            │
│   • Harder to optimize                                                      │
│                                                                              │
│   Why use it anyway?                                                         │
│   • Perfect for learning                                                    │
│   • JVM and Python prove it works at scale                                  │
│   • Can add JIT later for speed                                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Understanding

### Question 1
After `PUSH_I32 1; PUSH_I32 2; PUSH_I32 3`, what's on the stack?

Answer: `[1][2][3]` with 3 on top.

### Question 2
For `10 / 2`, what bytecode do we generate?

Answer: `PUSH_I32 10; PUSH_I32 2; DIV_I32` - push left operand first.

### Question 3
After `PUSH_I32 5; PUSH_I32 3; SUB_I32`, what value is on the stack?

Answer: `2` (5 - 3 = 2). First operand pushed becomes left operand.

---

## What's Next

Let's generate bytecode for constants.

Next: [Lesson 5c.4: Generating Constants](../04-gen-constants/) →
