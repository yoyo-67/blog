---
title: "2.5: Statements"
weight: 5
---

# Lesson 2.5: Statements

Expressions produce values. Statements DO things.

---

## Goal

Parse statements: `const x = 5;` and `return x;`

---

## Expressions vs Statements

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    EXPRESSIONS VS STATEMENTS                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   EXPRESSIONS produce a value:                                              │
│     42              → produces 42                                           │
│     x + y           → produces the sum                                      │
│     foo()           → produces return value                                 │
│                                                                              │
│   STATEMENTS perform an action:                                             │
│     const x = 5;    → creates a variable (no value produced)               │
│     return 42;      → exits the function (no value produced)               │
│     { ... }         → groups statements (no value produced)                │
│                                                                              │
│   Key difference: statements usually end with semicolons.                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Expressions vs Statements vs Declarations

```
┌──────────────────────────────────────────────────────────────────────────────┐
│              EXPRESSIONS VS STATEMENTS VS DECLARATIONS                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   EXPRESSIONS: Produce a value                                              │
│   ─────────────────────────────                                             │
│     1 + 2           → 3                                                     │
│     x * y           → some number                                           │
│     foo()           → return value of foo                                   │
│                                                                              │
│   STATEMENTS: Do something (perform an action)                              │
│   ────────────────────────────────────────────                              │
│     return x;       → exits function with value x                           │
│     print(x);       → outputs x (if your language has this)                │
│     { ... }         → groups other statements                              │
│                                                                              │
│   DECLARATIONS: Create a new named thing                                    │
│   ──────────────────────────────────────────                                │
│     const x = 5;    → creates variable x                                   │
│     fn foo() {...}  → creates function foo                                 │
│                                                                              │
│   Declarations are a special kind of statement that introduces a name.     │
│                                                                              │
│   In our grammar, we'll treat declarations as statements for simplicity.   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Statement Grammar Rules

```
statement   → var_decl | return_stmt
var_decl    → "const" IDENTIFIER "=" expression ";"
return_stmt → "return" expression ";"
```

Let's break these down:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         STATEMENT RULES                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   statement → var_decl | return_stmt                                        │
│                                                                              │
│   A statement is EITHER a variable declaration OR a return statement.       │
│   We look at the first token to decide which one.                           │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────     │
│                                                                              │
│   var_decl → "const" IDENTIFIER "=" expression ";"                          │
│                                                                              │
│   A variable declaration is:                                                 │
│     - the keyword "const"                                                   │
│     - an identifier (the variable name)                                     │
│     - an equals sign                                                        │
│     - an expression (the value)                                             │
│     - a semicolon                                                           │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────     │
│                                                                              │
│   return_stmt → "return" expression ";"                                     │
│                                                                              │
│   A return statement is:                                                     │
│     - the keyword "return"                                                  │
│     - an expression (the return value)                                      │
│     - a semicolon                                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Trace of `const x = 1 + 2;`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "const x = 1 + 2;"                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [CONST] [x] [=] [1] [+] [2] [;]                                   │
│            ▲                                                                 │
│                                                                              │
│   statement():                                                               │
│       see "const"? Yes!                                                      │
│       call var_decl():                                                       │
│           expect "const" → consume                                          │
│                                                                              │
│           Tokens: [CONST] [x] [=] [1] [+] [2] [;]                           │
│                          ▲                                                   │
│                                                                              │
│           expect IDENTIFIER → consume, name = "x"                           │
│                                                                              │
│           Tokens: [CONST] [x] [=] [1] [+] [2] [;]                           │
│                              ▲                                               │
│                                                                              │
│           expect "=" → consume                                              │
│                                                                              │
│           Tokens: [CONST] [x] [=] [1] [+] [2] [;]                           │
│                                  ▲                                           │
│                                                                              │
│           call expression():                                                 │
│               ... parses "1 + 2" ...                                        │
│               returns Add(1, 2)                                             │
│           value = Add(1, 2)                                                 │
│                                                                              │
│           Tokens: [CONST] [x] [=] [1] [+] [2] [;]                           │
│                                              ▲                               │
│                                                                              │
│           expect ";" → consume                                              │
│           return VarDecl { name: "x", value: Add(1, 2) }                   │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tree:                                                                      │
│           VarDecl                                                            │
│          /       \                                                           │
│        "x"       Add                                                         │
│                 /   \                                                        │
│                1     2                                                       │
│                                                                              │
│   The key: var_decl CALLS expression for the value!                        │
│   This is how the grammar COMPOSES.                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Trace of `return x + 1;`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "return x + 1;"                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [RETURN] [x] [+] [1] [;]                                          │
│            ▲                                                                 │
│                                                                              │
│   statement():                                                               │
│       see "const"? No                                                        │
│       see "return"? Yes!                                                     │
│       call return_stmt():                                                    │
│           expect "return" → consume                                         │
│                                                                              │
│           Tokens: [RETURN] [x] [+] [1] [;]                                  │
│                           ▲                                                  │
│                                                                              │
│           call expression():                                                 │
│               call term():                                                   │
│                   call unary():                                              │
│                       call primary():                                        │
│                           see IDENTIFIER "x" → return Ident("x")           │
│               left = Ident("x")                                             │
│               see "+"? Yes → consume                                        │
│               call term():                                                   │
│                   returns 1                                                 │
│               left = Add(Ident("x"), 1)                                     │
│               return Add(Ident("x"), 1)                                     │
│           value = Add(Ident("x"), 1)                                        │
│                                                                              │
│           Tokens: [RETURN] [x] [+] [1] [;]                                  │
│                                       ▲                                      │
│                                                                              │
│           expect ";" → consume                                              │
│           return ReturnStmt { value: Add(Ident("x"), 1) }                  │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tree:                                                                      │
│           ReturnStmt                                                         │
│               |                                                              │
│              Add                                                             │
│             /   \                                                            │
│         Ident   1                                                           │
│           |                                                                  │
│          "x"                                                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## How Statements Contain Expressions

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                   STATEMENTS CONTAIN EXPRESSIONS                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   const x = 1 + 2;                                                          │
│   ─────────────────                                                          │
│         │     └───┴─── expression (produces a value)                        │
│         │                                                                    │
│         └─── statement (performs action: creates variable)                  │
│                                                                              │
│   return x * y;                                                             │
│   ─────────────                                                              │
│         │  └──┴─── expression (produces a value)                            │
│         │                                                                    │
│         └─── statement (performs action: exits function)                    │
│                                                                              │
│   Statements often CONTAIN expressions.                                      │
│   The expression provides the VALUE that the statement uses.                │
│                                                                              │
│   Grammar shows this clearly:                                                │
│     var_decl    → "const" IDENTIFIER "=" expression ";"                     │
│     return_stmt → "return" expression ";"                                   │
│                                     ──────────                               │
│                                         │                                    │
│                                         └─── statements CALL expression     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Translating to Code

```
// Grammar:
//   statement   → var_decl | return_stmt
//   var_decl    → "const" IDENTIFIER "=" expression ";"
//   return_stmt → "return" expression ";"

function parseStatement():
    if see(CONST):
        return parseVarDecl()

    if see(RETURN):
        return parseReturnStmt()

    error("Expected statement")

function parseVarDecl():
    expect(CONST)                    // "const"
    name = expect(IDENTIFIER).lexeme // variable name
    expect(EQUAL)                    // "="
    value = parseExpression()        // the value
    expect(SEMICOLON)                // ";"
    return VarDeclNode(name, value)

function parseReturnStmt():
    expect(RETURN)                   // "return"
    value = parseExpression()        // the return value
    expect(SEMICOLON)                // ";"
    return ReturnStmtNode(value)
```

---

## Looking Ahead: How Statement Decides

The parser looks at the **first token** to decide which kind of statement:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    DECIDING WHICH STATEMENT                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   parseStatement() looks at the current token:                              │
│                                                                              │
│     First token     →    Parse as                                           │
│     ───────────          ────────                                           │
│     "const"         →    parseVarDecl()                                     │
│     "return"        →    parseReturnStmt()                                  │
│     anything else   →    error!                                             │
│                                                                              │
│   This is called "looking ahead" or "peeking".                              │
│   We don't consume the token yet - just look at it.                         │
│                                                                              │
│   Code pattern:                                                              │
│                                                                              │
│     function parseStatement():                                               │
│         if see(CONST):         // peek at current token                     │
│             return parseVarDecl()                                           │
│         if see(RETURN):        // peek at current token                     │
│             return parseReturnStmt()                                        │
│         error("Expected statement")                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Implementation

### Test 1: Variable declaration with number
```
Input:  "const x = 42;"
AST:    VarDeclNode {
            name: "x",
            value: NumberNode(42)
        }
```

### Test 2: Variable declaration with expression
```
Input:  "const result = 1 + 2 * 3;"
AST:    VarDeclNode {
            name: "result",
            value: AddNode {
                left: NumberNode(1),
                right: MulNode {
                    left: NumberNode(2),
                    right: NumberNode(3)
                }
            }
        }
```

### Test 3: Return statement
```
Input:  "return 0;"
AST:    ReturnStmtNode {
            value: NumberNode(0)
        }
```

### Test 4: Return with expression
```
Input:  "return x + 1;"
AST:    ReturnStmtNode {
            value: AddNode {
                left: IdentifierNode("x"),
                right: NumberNode(1)
            }
        }
```

### Test 5: Missing semicolon (error)
```
Input:  "const x = 5"
Result: Error - Expected ";"
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Expressions produce values:   1 + 2, x * y, foo()                         │
│   Statements perform actions:   const x = 5;  return x;                     │
│                                                                              │
│   Statement grammar:                                                         │
│     statement   → var_decl | return_stmt                                    │
│     var_decl    → "const" IDENTIFIER "=" expression ";"                     │
│     return_stmt → "return" expression ";"                                   │
│                                                                              │
│   Key pattern: statements CONTAIN expressions                               │
│     - var_decl calls parseExpression() for the value                       │
│     - return_stmt calls parseExpression() for the return value             │
│                                                                              │
│   Decision pattern: look at first token                                     │
│     - "const" → parse variable declaration                                  │
│     - "return" → parse return statement                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

We can parse single statements. But functions have multiple statements in a block: `{ const x = 5; return x; }`. And functions themselves need parsing.

Next: [Lesson 2.6: Functions](../06-functions/) →
