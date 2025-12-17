---
title: "2.9: Blocks"
weight: 9
---

# Lesson 2.9: Code Blocks

Blocks group multiple statements: `{ stmt; stmt; }`

---

## Goal

Parse `{ ... }` into Block nodes containing a list of statements.

---

## What Are Blocks?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              BLOCKS                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   {                                                                         │
│       const x: i32 = 1;                                                     │
│       const y: i32 = 2;                                                     │
│       return x + y;                                                         │
│   }                                                                         │
│                                                                              │
│   A block is:                                                               │
│   - Opening brace {                                                         │
│   - Zero or more statements                                                 │
│   - Closing brace }                                                         │
│                                                                              │
│   Blocks are used for:                                                      │
│   - Function bodies                                                         │
│   - If/else bodies (future extension)                                       │
│   - Loop bodies (future extension)                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Block AST

```
Block {
    statements: Statement[]
}
```

---

## parseBlock

```
function parseBlock():
    expect(LBRACE)     // {

    statements = []

    while peek().type != RBRACE and not isAtEnd():
        stmt = parseStatement()
        statements.append(stmt)

    expect(RBRACE)     // }

    return Block {
        statements: statements
    }
```

---

## Step-by-Step Trace

```
Input: "{ const x: i32 = 1; return x; }"

Tokens: [LBRACE, CONST, IDENT("x"), COLON, TYPE_I32, EQUAL,
         NUMBER(1), SEMI, RETURN, IDENT("x"), SEMI, RBRACE, EOF]

parseBlock():
    expect(LBRACE) ✓
    statements = []

    Loop 1:
        peek() → CONST (not RBRACE)
        parseStatement() → VarDecl { name: "x", value: 1 }
        statements = [VarDecl]

    Loop 2:
        peek() → RETURN (not RBRACE)
        parseStatement() → ReturnStmt { value: Identifier("x") }
        statements = [VarDecl, ReturnStmt]

    Loop 3:
        peek() → RBRACE
        exit loop

    expect(RBRACE) ✓

    return Block { statements: [VarDecl, ReturnStmt] }

Result:
Block {
    statements: [
        VarDecl { name: "x", type: i32, value: 1, is_const: true },
        ReturnStmt { value: IdentifierExpr { name: "x" } }
    ]
}
```

---

## Empty Blocks

Blocks can be empty:

```
{ }

Block { statements: [] }
```

---

## Nested Blocks

Blocks can contain blocks (for future scoping):

```
{
    const x: i32 = 1;
    {
        const y: i32 = 2;
    }
}
```

To support this, add LBRACE to parseStatement:

```
function parseStatement():
    token = peek()

    if token.type == KEYWORD_CONST or token.type == KEYWORD_VAR:
        return parseVarDecl()

    if token.type == KEYWORD_RETURN:
        return parseReturnStmt()

    if token.type == LBRACE:           // ← ADD THIS
        return parseBlock()             // Blocks can be statements

    error("Expected statement, got " + token.type)
```

---

## Verify Your Implementation

### Test 1: Simple block
```
Input:  "{ return 42; }"
AST:    Block {
            statements: [
                ReturnStmt { value: NumberExpr(42) }
            ]
        }
```

### Test 2: Multiple statements
```
Input:  "{ const x: i32 = 1; const y: i32 = 2; return x + y; }"
AST:    Block {
            statements: [
                VarDecl { name: "x", value: NumberExpr(1) },
                VarDecl { name: "y", value: NumberExpr(2) },
                ReturnStmt { value: BinaryExpr(x, +, y) }
            ]
        }
```

### Test 3: Empty block
```
Input:  "{ }"
AST:    Block { statements: [] }
```

### Test 4: Nested blocks
```
Input:  "{ { return 1; } }"
AST:    Block {
            statements: [
                Block {
                    statements: [
                        ReturnStmt { value: NumberExpr(1) }
                    ]
                }
            ]
        }
```

### Test 5: Missing closing brace
```
Input:  "{ return 42;"
Result: Error - Expected RBRACE, got EOF
```

### Test 6: Missing opening brace
```
Input:  "return 42; }"
Result: Error - depends on context
```

---

## Block Scope (Preview)

In semantic analysis, blocks create new scopes:

```
{
    const x: i32 = 1;
    {
        const x: i32 = 2;    // Different x! Shadows outer x
        return x;             // Returns 2
    }
    return x;                 // Returns 1
}
```

For now, we just parse the structure. Scope resolution comes later.

---

## What's Next

We have all the pieces for function bodies. Let's parse function declarations.

Next: [Lesson 2.10: Functions](../10-functions/) →
