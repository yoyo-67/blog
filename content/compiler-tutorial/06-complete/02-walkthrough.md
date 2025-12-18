---
title: "6.2: Walkthrough"
weight: 2
---

# Lesson 6.2: Complete Walkthrough

Trace a program through every stage of compilation.

---

## Goal

Follow a program through Lexer → Parser → ZIR → Sema → Codegen.

---

## The Source Program

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn main() i32 {
    const result: i32 = add(3, 5);
    return result;
}
```

Wait - we don't have function calls! Let's use a simpler program:

```
fn main() i32 {
    const x: i32 = 3;
    const y: i32 = 5;
    const sum: i32 = x + y;
    return sum;
}
```

---

## Stage 1: Lexer

Input: Source code string

Output: Token stream

```
Source: "fn main() i32 { const x: i32 = 3; const y: i32 = 5; const sum: i32 = x + y; return sum; }"

Tokens:
[KEYWORD_FN, IDENTIFIER("main"), LPAREN, RPAREN, TYPE_I32, LBRACE,
 KEYWORD_CONST, IDENTIFIER("x"), COLON, TYPE_I32, EQUAL, NUMBER("3"), SEMICOLON,
 KEYWORD_CONST, IDENTIFIER("y"), COLON, TYPE_I32, EQUAL, NUMBER("5"), SEMICOLON,
 KEYWORD_CONST, IDENTIFIER("sum"), COLON, TYPE_I32, EQUAL, IDENTIFIER("x"), PLUS, IDENTIFIER("y"), SEMICOLON,
 KEYWORD_RETURN, IDENTIFIER("sum"), SEMICOLON,
 RBRACE, EOF]
```

---

## Stage 2: Parser

Input: Token stream

Output: Abstract Syntax Tree

```
Root {
    declarations: [
        FnDecl {
            name: "main",
            params: [],
            return_type: TypeExpr("i32"),
            body: Block {
                statements: [
                    VarDecl {
                        name: "x",
                        type: TypeExpr("i32"),
                        value: NumberExpr(3),
                        is_const: true
                    },
                    VarDecl {
                        name: "y",
                        type: TypeExpr("i32"),
                        value: NumberExpr(5),
                        is_const: true
                    },
                    VarDecl {
                        name: "sum",
                        type: TypeExpr("i32"),
                        value: BinaryExpr {
                            left: IdentifierExpr("x"),
                            operator: PLUS,
                            right: IdentifierExpr("y")
                        },
                        is_const: true
                    },
                    ReturnStmt {
                        value: IdentifierExpr("sum")
                    }
                ]
            }
        }
    ]
}
```

---

## Stage 3: ZIR Generation

Input: AST

Output: Untyped intermediate representation

```
function "main":
  params: []
  return_type: i32
  body:
    %0 = constant(3)
    %1 = decl("x", %0)
    %2 = constant(5)
    %3 = decl("y", %2)
    %4 = decl_ref("x")
    %5 = decl_ref("y")
    %6 = add(%4, %5)
    %7 = decl("sum", %6)
    %8 = decl_ref("sum")
    %9 = ret(%8)
```

---

## Stage 4: Sema

Input: ZIR

Output: Typed AIR + Symbol table

```
Symbol Table (after processing):
  "x":   { kind: LOCAL, slot: 0, type: I32 }
  "y":   { kind: LOCAL, slot: 1, type: I32 }
  "sum": { kind: LOCAL, slot: 2, type: I32 }

Type of each instruction:
  %0: I32      (constant)
  %1: VOID     (declaration)
  %2: I32      (constant)
  %3: VOID     (declaration)
  %4: I32      (local_get)
  %5: I32      (local_get)
  %6: I32      (add_i32)
  %7: VOID     (declaration)
  %8: I32      (local_get)
  %9: I32      (return)

AIR:
  function "main":
    params: []
    return_type: i32
    local_count: 3
    body:
      %0 = const_i32(3)
      %1 = local_set(slot: 0, value: %0)
      %2 = const_i32(5)
      %3 = local_set(slot: 1, value: %2)
      %4 = local_get(slot: 0)
      %5 = local_get(slot: 1)
      %6 = add_i32(%4, %5)
      %7 = local_set(slot: 2, value: %6)
      %8 = local_get(slot: 2)
      %9 = ret(%8)
```

---

## Stage 5: Codegen

Input: AIR

Output: C code

```c
#include <stdint.h>
#include <stdbool.h>

int32_t main();

int32_t main() {
    int32_t local_0;
    int32_t local_1;
    int32_t local_2;

    int32_t t0 = 3;
    local_0 = t0;
    int32_t t2 = 5;
    local_1 = t2;
    int32_t t4 = local_0;
    int32_t t5 = local_1;
    int32_t t6 = t4 + t5;
    local_2 = t6;
    int32_t t8 = local_2;
    return t8;
}
```

---

## Stage 6: C Compiler

Input: C code

Output: Executable

```bash
$ cc output.c -o program
$ ./program
$ echo $?
8
```

The program correctly computes 3 + 5 = 8!

---

## Optimization by C Compiler

With `cc -O2`, the C compiler optimizes away all the temporaries:

```bash
$ cc -O2 -S output.c -o output.s
$ cat output.s
```

The generated assembly might be as simple as:
```asm
main:
    mov eax, 8    ; Just return 8!
    ret
```

The C compiler knows 3 + 5 = 8 at compile time.

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      COMPLETE PIPELINE                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source:   "fn main() i32 { ... }"                                         │
│       ↓                                                                      │
│   Tokens:   [FN, IDENT("main"), LPAREN, ...]                                │
│       ↓                                                                      │
│   AST:      FnDecl { name: "main", body: Block { ... } }                   │
│       ↓                                                                      │
│   ZIR:      %0 = constant(3), %1 = decl("x", %0), ...                      │
│       ↓                                                                      │
│   AIR:      %0 = const_i32(3), %1 = local_set(0, %0), ...                  │
│       ↓                                                                      │
│   C Code:   int32_t main() { int32_t t0 = 3; ... }                         │
│       ↓                                                                      │
│   Binary:   ./program → returns 8                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

Let's build a comprehensive test suite.

Next: [Lesson 6.3: Test Suite](../03-test-suite/) →
