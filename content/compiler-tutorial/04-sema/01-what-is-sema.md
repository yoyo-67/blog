---
title: "4.1: What is Semantic Analysis?"
weight: 1
---

# Lesson 4.1: What is Semantic Analysis?

The parser checks structure. Sema checks meaning.

---

## Goal

Understand what semantic analysis does and why we need it.

---

## The Problem

The parser accepts code that looks right but is wrong:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      PARSER vs SEMA                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Parser says OK:                 Sema says ERROR:                          │
│                                                                              │
│   fn foo() i32 {                  fn foo() i32 {                            │
│       return x;                       return x;     ← x doesn't exist!      │
│   }                               }                                          │
│                                                                              │
│   fn bar() i32 {                  fn bar() i32 {                            │
│       const x = 1;                    const x = 1;                          │
│       const x = 2;                    const x = 2;  ← x already declared!   │
│       return x;                       return x;                              │
│   }                               }                                          │
│                                                                              │
│   Parser: "Syntax is valid!"                                                 │
│   Sema:   "But it doesn't make sense!"                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What Sema Checks

We'll implement three checks:

```
1. UNDEFINED VARIABLES
   return x;           → Is x declared?

2. DUPLICATE DECLARATIONS
   const x = 1;
   const x = 2;        → Is x already declared?

3. RETURN TYPE MISMATCH
   fn foo() i32 {
       return true;    → Does bool match i32?
   }
```

---

## Where Sema Fits

```
Source Code
    │
    ▼
┌─────────┐
│  Lexer  │  → Tokens
└────┬────┘
     │
     ▼
┌─────────┐
│ Parser  │  → AST
└────┬────┘
     │
     ▼
┌─────────┐
│   ZIR   │  → Instructions
└────┬────┘
     │
     ▼
┌─────────┐
│  SEMA   │  → Errors          ← WE ARE HERE
└─────────┘
```

---

## Input: ZIR Instructions

Sema analyzes ZIR. Here's what we're working with:

```
Source:
fn foo() i32 {
    const x = 10;
    return x;
}

ZIR:
    %0 = constant(10)
    %1 = decl("x", %0)
    %2 = decl_ref("x")
    %3 = ret(%2)
```

---

## Output: Errors

When sema finds problems, it produces error messages:

```
1:19: error: undefined variable "x"
fn foo() i32 { return x; }
                      ^
```

Good error messages include:
- **Line and column** - where
- **Description** - what
- **Source snippet** - context
- **Caret** - exact spot

---

## The Analysis Loop

```
function analyzeFunction(func):
    for each instruction in func:
        switch instruction:

            constant:
                // Nothing to check

            decl_ref("x"):
                if "x" not declared:
                    error: undefined variable

            decl("x", value):
                if "x" already declared:
                    error: duplicate declaration

            return_stmt(value):
                if value type != function return type:
                    error: return type mismatch
```

---

## Verify Your Understanding

### Question 1: What error?
```
fn foo() i32 {
    return x;
}
```
**Answer:** `undefined variable "x"` - x was never declared.

### Question 2: What error?
```
fn foo() i32 {
    const x = 1;
    const x = 2;
    return x;
}
```
**Answer:** `duplicate declaration "x"` - x is declared twice.

### Question 3: What error?
```
fn foo(n: i64) i32 {
    return n;
}
```
**Answer:** `return type mismatch: expected i32, got i64`

### Question 4: No error?
```
fn foo() i32 {
    const x = 10;
    return x;
}
```
**Answer:** No error - x is declared before use, return type matches.

---

## What's Next

First, let's understand how errors point back to source code locations.

Next: [Lesson 4.2: The Pointer Chain](../02-pointer-chain/) →
