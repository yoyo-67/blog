---
title: "5b.2: LLVM IR Basics"
weight: 2
---

# Lesson 5b.2: LLVM IR Basics

Understanding LLVM's intermediate representation.

---

## Goal

Learn the structure and syntax of LLVM IR.

---

## LLVM IR Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         LLVM IR HIERARCHY                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   MODULE                    (one .ll file)                                   │
│   │                                                                          │
│   ├── Global Variables      @global_var = global i32 0                      │
│   │                                                                          │
│   ├── Function Declarations declare i32 @printf(i8*, ...)                   │
│   │                                                                          │
│   └── Function Definitions                                                   │
│       │                                                                      │
│       └── FUNCTION          define i32 @main() { ... }                      │
│           │                                                                  │
│           └── BASIC BLOCKS  Named sequences of instructions                 │
│               │                                                              │
│               └── INSTRUCTIONS  %1 = add i32 %a, %b                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## A Complete Example

```llvm
; Module-level comments start with semicolon

; Function definition
define i32 @add(i32 %a, i32 %b) {
entry:                              ; Basic block label
    %result = add i32 %a, %b        ; Instruction
    ret i32 %result                 ; Return instruction
}

define i32 @main() {
entry:
    %sum = call i32 @add(i32 3, i32 5)
    ret i32 %sum
}
```

---

## Naming Conventions

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         LLVM NAMING                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   PREFIX    MEANING              EXAMPLE                                     │
│   ──────    ───────              ───────                                     │
│   @         Global (functions,   @main, @printf, @global_var                │
│             global variables)                                                │
│                                                                              │
│   %         Local (parameters,   %a, %result, %0, %1                        │
│             local values)                                                    │
│                                                                              │
│   Numbers can be used: %0, %1, %2 (unnamed temporaries)                     │
│   Names can be used: %result, %sum (named values)                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Basic Types

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         LLVM TYPES                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   INTEGERS                                                                   │
│   i1       1-bit integer (boolean)                                          │
│   i8       8-bit integer                                                    │
│   i16      16-bit integer                                                   │
│   i32      32-bit integer                                                   │
│   i64      64-bit integer                                                   │
│   i128     128-bit integer                                                  │
│                                                                              │
│   FLOATING POINT                                                             │
│   float    32-bit float                                                     │
│   double   64-bit float                                                     │
│                                                                              │
│   OTHER                                                                      │
│   void     No value                                                         │
│   i8*      Pointer to i8 (like char*)                                       │
│   [10 x i32]  Array of 10 i32s                                              │
│   {i32, i64}  Struct with i32 and i64                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## SSA Form

LLVM IR uses Static Single Assignment (SSA) form:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SSA FORM                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Rule: Each variable is assigned exactly ONCE                               │
│                                                                              │
│   NOT SSA (imperative):          SSA form:                                   │
│   ─────────────────────          ─────────                                   │
│   x = 1                          %x1 = 1                                    │
│   x = x + 1                      %x2 = add i32 %x1, 1                       │
│   x = x * 2                      %x3 = mul i32 %x2, 2                       │
│                                                                              │
│   Each "version" of x gets a new name!                                       │
│                                                                              │
│   Why SSA?                                                                   │
│   • Makes data flow explicit                                                 │
│   • Enables many optimizations                                               │
│   • Matches our AIR structure                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Basic Instructions

### Arithmetic

```llvm
; Binary operations: result = op type operand1, operand2
%sum = add i32 %a, %b       ; Addition
%diff = sub i32 %a, %b      ; Subtraction
%prod = mul i32 %a, %b      ; Multiplication
%quot = sdiv i32 %a, %b     ; Signed division
%rem = srem i32 %a, %b      ; Signed remainder

; Floating point
%fsum = fadd float %x, %y
%fprod = fmul double %x, %y
```

### Comparison

```llvm
; Integer comparison (returns i1)
%eq = icmp eq i32 %a, %b    ; Equal
%ne = icmp ne i32 %a, %b    ; Not equal
%lt = icmp slt i32 %a, %b   ; Signed less than
%gt = icmp sgt i32 %a, %b   ; Signed greater than

; Float comparison
%feq = fcmp oeq float %x, %y  ; Ordered equal
```

### Control Flow

```llvm
; Unconditional branch
br label %next_block

; Conditional branch
br i1 %condition, label %if_true, label %if_false

; Return
ret i32 %value
ret void
```

---

## Function Definitions

```llvm
; Function syntax
define <return_type> @<name>(<params>) {
<basic_blocks>
}

; Example: function with two parameters
define i32 @multiply(i32 %x, i32 %y) {
entry:
    %result = mul i32 %x, %y
    ret i32 %result
}

; Void function
define void @print_value(i32 %val) {
entry:
    ; ... do something
    ret void
}
```

---

## Basic Blocks

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         BASIC BLOCKS                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   A basic block is:                                                          │
│   • A sequence of instructions                                               │
│   • Starts with a label                                                      │
│   • Ends with a terminator (ret, br)                                        │
│   • No branches in the middle                                                │
│                                                                              │
│   define i32 @abs(i32 %x) {                                                 │
│   entry:                          ; Block 1                                  │
│       %is_neg = icmp slt i32 %x, 0                                          │
│       br i1 %is_neg, label %negate, label %done                             │
│                                                                              │
│   negate:                         ; Block 2                                  │
│       %neg = sub i32 0, %x                                                  │
│       br label %done                                                         │
│                                                                              │
│   done:                           ; Block 3                                  │
│       %result = phi i32 [%neg, %negate], [%x, %entry]                       │
│       ret i32 %result                                                        │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Phi Nodes

When control flow merges, use `phi` to select values:

```llvm
; phi selects value based on which block we came from
%result = phi i32 [%val1, %block1], [%val2, %block2]

; Example: max function
define i32 @max(i32 %a, i32 %b) {
entry:
    %cond = icmp sgt i32 %a, %b
    br i1 %cond, label %use_a, label %use_b

use_a:
    br label %done

use_b:
    br label %done

done:
    %result = phi i32 [%a, %use_a], [%b, %use_b]
    ret i32 %result
}
```

---

## Our Simple Subset

For our mini compiler, we only need:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    MINI COMPILER LLVM SUBSET                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Types:          i32, i64, void                                            │
│                                                                              │
│   Instructions:   add, sub, mul, sdiv (arithmetic)                          │
│                   ret (return)                                               │
│                   call (if we add function calls)                           │
│                                                                              │
│   Structure:      One entry block per function                              │
│                   No control flow (no branches yet)                          │
│                   No phi nodes needed                                        │
│                                                                              │
│   This matches what we generate with the C backend!                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Understanding

### Question 1
What prefix is used for local values in LLVM IR?

Answer: `%` (percent sign). Global values use `@`.

### Question 2
Why does LLVM use SSA form?

Answer: Each value is assigned once, making data flow explicit and enabling optimizations.

### Question 3
What terminates a basic block?

Answer: A terminator instruction like `ret` or `br`.

---

## What's Next

Let's map our compiler's types to LLVM types.

Next: [Lesson 5b.3: Type Mapping](../03-type-mapping/) →
