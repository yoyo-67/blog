---
title: "2.6: Functions"
weight: 6
---

# Lesson 2.6: Blocks and Functions

Parse function declarations: `fn add(a: i32, b: i32) { return a + b; }`

---

## Goal

Parse blocks and function declarations to complete our grammar.

---

## Blocks

A **block** is a sequence of statements wrapped in braces.

### The Grammar Rule

```
block → "{" statement* "}"
```

This says: an open brace, zero or more statements, and a close brace.

---

## Trace of `{ const x = 5; return x; }`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│              PARSING "{ const x = 5; return x; }"                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [{] [CONST] [x] [=] [5] [;] [RETURN] [x] [;] [}]                  │
│            ▲                                                                 │
│                                                                              │
│   block():                                                                   │
│       expect "{" → consume                                                  │
│       statements = []                                                        │
│                                                                              │
│       while not see "}":                                                    │
│           call statement():                                                  │
│               ... parses "const x = 5;" ...                                 │
│               returns VarDecl { name: "x", value: 5 }                       │
│           append to statements                                              │
│                                                                              │
│           call statement():                                                  │
│               ... parses "return x;" ...                                    │
│               returns ReturnStmt { value: Ident("x") }                      │
│           append to statements                                              │
│                                                                              │
│       expect "}" → consume                                                  │
│       return Block { statements: [VarDecl, ReturnStmt] }                    │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tree:                                                                      │
│           Block                                                              │
│          /     \                                                             │
│     VarDecl   ReturnStmt                                                    │
│     /    \         |                                                         │
│   "x"     5    Ident("x")                                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Functions

Now let's add function declarations.

### The Grammar Rules

```
function   → "fn" IDENTIFIER "(" parameters? ")" block
parameters → parameter ("," parameter)*
parameter  → IDENTIFIER ":" type
type       → "i32" | "bool" | "void"
```

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       FUNCTION GRAMMAR RULES                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   function → "fn" IDENTIFIER "(" parameters? ")" block                      │
│                                                                              │
│   This says: a function is:                                                 │
│     1. The keyword "fn"                                                     │
│     2. An identifier (the function name)                                    │
│     3. Open paren                                                           │
│     4. OPTIONAL parameters (that's what ? means)                            │
│     5. Close paren                                                          │
│     6. A block                                                              │
│                                                                              │
│   ────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   parameters → parameter ("," parameter)*                                   │
│                                                                              │
│   This says: parameters are:                                                │
│     1. One parameter                                                        │
│     2. Followed by zero or more (comma, parameter) pairs                   │
│                                                                              │
│   Examples:                                                                  │
│     "a: i32"           → one parameter                                      │
│     "a: i32, b: i32"   → two parameters                                    │
│     ""                 → no parameters (handled by the ? in function)       │
│                                                                              │
│   ────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   parameter → IDENTIFIER ":" type                                           │
│                                                                              │
│   This says: a parameter is an identifier, a colon, and a type.            │
│                                                                              │
│   Example: "a: i32"                                                         │
│     IDENTIFIER = "a"                                                        │
│     ":"                                                                      │
│     type = "i32"                                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The `?` Operator

The `?` means "optional" - zero or one occurrence:

```
parameters?

Matches:
  ""           (nothing - zero occurrences)   ✓
  "a: i32"     (one occurrence)               ✓
```

In code, we check if we see a parameter before trying to parse:

```
if not see(RPAREN):
    params = parseParameters()
```

---

## Trace of `fn add(a: i32, b: i32) { return a + b; }`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│        PARSING "fn add(a: i32, b: i32) { return a + b; }"                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [FN] [add] [(] [a] [:] [i32] [,] [b] [:] [i32] [)]                │
│           [{] [RETURN] [a] [+] [b] [;] [}]                                  │
│            ▲                                                                 │
│                                                                              │
│   function():                                                                │
│       expect "fn" → consume                                                 │
│       expect IDENTIFIER → consume, name = "add"                             │
│       expect "(" → consume                                                  │
│                                                                              │
│       see ")"? No, so parse parameters                                      │
│       call parameters():                                                     │
│           call parameter():                                                  │
│               expect IDENTIFIER → consume, name = "a"                       │
│               expect ":" → consume                                          │
│               expect type → consume, type = "i32"                           │
│               return Parameter { name: "a", type: "i32" }                   │
│                                                                              │
│           see ","? Yes → consume                                            │
│                                                                              │
│           call parameter():                                                  │
│               expect IDENTIFIER → consume, name = "b"                       │
│               expect ":" → consume                                          │
│               expect type → consume, type = "i32"                           │
│               return Parameter { name: "b", type: "i32" }                   │
│                                                                              │
│           see ","? No                                                       │
│           return [Param("a"), Param("b")]                                   │
│                                                                              │
│       params = [Param("a"), Param("b")]                                     │
│       expect ")" → consume                                                  │
│                                                                              │
│       call block():                                                          │
│           expect "{" → consume                                              │
│           call statement():                                                  │
│               call return_stmt():                                            │
│                   expect "return" → consume                                 │
│                   call expression():                                         │
│                       ... parses "a + b" ...                                │
│                       returns Add(Ident("a"), Ident("b"))                   │
│                   expect ";" → consume                                      │
│                   return ReturnStmt { value: Add(...) }                     │
│           expect "}" → consume                                              │
│           return Block { statements: [ReturnStmt] }                         │
│                                                                              │
│       return FnDecl {                                                        │
│           name: "add",                                                       │
│           params: [Param("a", i32), Param("b", i32)],                       │
│           body: Block { ... }                                               │
│       }                                                                      │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tree:                                                                      │
│                    FnDecl("add")                                             │
│                   /      |       \                                           │
│           Param("a")  Param("b")  Block                                     │
│              |           |           |                                       │
│            i32         i32      ReturnStmt                                  │
│                                      |                                       │
│                                     Add                                      │
│                                    /   \                                     │
│                               Ident   Ident                                  │
│                                 |       |                                    │
│                                "a"     "b"                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Program: Multiple Functions

A program is just a sequence of functions:

```
program → function*
```

This lets us parse multiple functions:

```
fn main() {
    return add(1, 2);
}

fn add(a: i32, b: i32) {
    return a + b;
}
```

---

## Translating to Code

```
// Grammar:
//   program    → function*
//   function   → "fn" IDENTIFIER "(" parameters? ")" block
//   parameters → parameter ("," parameter)*
//   parameter  → IDENTIFIER ":" type
//   block      → "{" statement* "}"

function parseProgram():
    functions = []
    while not see(EOF):
        fn = parseFunction()
        functions.append(fn)
    return ProgramNode(functions)

function parseFunction():
    expect(FN)                           // "fn"
    name = expect(IDENTIFIER).lexeme     // function name
    expect(LPAREN)                       // "("

    params = []
    if not see(RPAREN):                  // parameters?
        params = parseParameters()

    expect(RPAREN)                       // ")"
    body = parseBlock()                  // block

    return FunctionNode(name, params, body)

function parseParameters():
    params = []

    // First parameter
    params.append(parseParameter())

    // ("," parameter)*
    while see(COMMA):
        advance()                        // consume ","
        params.append(parseParameter())

    return params

function parseParameter():
    name = expect(IDENTIFIER).lexeme     // parameter name
    expect(COLON)                        // ":"
    type = parseType()                   // type
    return ParameterNode(name, type)

function parseBlock():
    expect(LBRACE)                       // "{"

    statements = []
    while not see(RBRACE):               // statement*
        stmt = parseStatement()
        statements.append(stmt)

    expect(RBRACE)                       // "}"
    return BlockNode(statements)
```

---

## Verify Your Implementation

### Test 1: Empty function
```
Input:  "fn main() { }"
AST:    FunctionNode {
            name: "main",
            params: [],
            body: BlockNode { statements: [] }
        }
```

### Test 2: Function with return
```
Input:  "fn main() { return 0; }"
AST:    FunctionNode {
            name: "main",
            params: [],
            body: BlockNode {
                statements: [
                    ReturnStmtNode { value: NumberNode(0) }
                ]
            }
        }
```

### Test 3: Function with one parameter
```
Input:  "fn inc(x: i32) { return x + 1; }"
AST:    FunctionNode {
            name: "inc",
            params: [ParameterNode { name: "x", type: "i32" }],
            body: BlockNode {
                statements: [
                    ReturnStmtNode {
                        value: AddNode {
                            left: IdentifierNode("x"),
                            right: NumberNode(1)
                        }
                    }
                ]
            }
        }
```

### Test 4: Function with multiple parameters
```
Input:  "fn add(a: i32, b: i32) { return a + b; }"
AST:    FunctionNode {
            name: "add",
            params: [
                ParameterNode { name: "a", type: "i32" },
                ParameterNode { name: "b", type: "i32" }
            ],
            body: BlockNode { ... }
        }
```

### Test 5: Multiple functions
```
Input:  "fn a() { } fn b() { }"
AST:    ProgramNode {
            functions: [
                FunctionNode { name: "a", ... },
                FunctionNode { name: "b", ... }
            ]
        }
```

---

## The Complete Grammar

Here's our full grammar with 12 rules:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         THE COMPLETE GRAMMAR                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   PROGRAM                                                                    │
│   ───────                                                                    │
│   program     → function*                                                   │
│                                                                              │
│   FUNCTIONS                                                                  │
│   ─────────                                                                  │
│   function    → "fn" IDENTIFIER "(" parameters? ")" block                   │
│   parameters  → parameter ("," parameter)*                                  │
│   parameter   → IDENTIFIER ":" type                                         │
│   type        → "i32" | "bool" | "void"                                     │
│                                                                              │
│   STATEMENTS                                                                 │
│   ──────────                                                                 │
│   block       → "{" statement* "}"                                          │
│   statement   → var_decl | return_stmt                                      │
│   var_decl    → "const" IDENTIFIER "=" expression ";"                       │
│   return_stmt → "return" expression ";"                                     │
│                                                                              │
│   EXPRESSIONS                                                                │
│   ───────────                                                                │
│   expression  → term (("+" | "-") term)*                                    │
│   term        → unary (("*" | "/") unary)*                                  │
│   unary       → "-" unary | primary                                         │
│   primary     → NUMBER | IDENTIFIER | "(" expression ")"                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Structure Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        GRAMMAR STRUCTURE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   program                                                                    │
│       │                                                                      │
│       └──► function*                                                        │
│               │                                                              │
│               ├──► parameters                                               │
│               │       │                                                      │
│               │       └──► parameter*                                       │
│               │               │                                              │
│               │               └──► type                                     │
│               │                                                              │
│               └──► block                                                    │
│                       │                                                      │
│                       └──► statement*                                       │
│                               │                                              │
│                               ├──► var_decl ──► expression                  │
│                               │                                              │
│                               └──► return_stmt ──► expression               │
│                                                       │                      │
│                                                       └──► term*            │
│                                                              │              │
│                                                              └──► unary*    │
│                                                                     │       │
│                                                                     └──► primary
│                                                                            │
│                                                              ┌─────────────┘
│                                                              │
│                                                              └──► expression
│                                                              (recursion!)
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Block:                                                                     │
│     Rule:   block → "{" statement* "}"                                      │
│     Code:   while not see(RBRACE): parseStatement()                         │
│                                                                              │
│   Function:                                                                  │
│     Rule:   function → "fn" IDENTIFIER "(" parameters? ")" block            │
│     Code:   parse name, optional params, then block                         │
│                                                                              │
│   Parameters:                                                                │
│     Rule:   parameters → parameter ("," parameter)*                         │
│     Code:   parse first, then while see(COMMA): parse more                  │
│                                                                              │
│   Program:                                                                   │
│     Rule:   program → function*                                             │
│     Code:   while not see(EOF): parseFunction()                             │
│                                                                              │
│   We now have a complete grammar for a simple language!                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

We've covered all the grammar rules. Let's put everything together with a complete parser implementation and common patterns.

Next: [Lesson 2.7: Complete Parser](../07-complete/) →
