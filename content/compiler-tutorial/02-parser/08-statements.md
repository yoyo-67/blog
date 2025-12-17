---
title: "2.8: Statements"
weight: 8
---

# Lesson 2.8: Statements

Statements are instructions that DO things: declare variables, return values.

---

## Goal

Parse `const`, `var`, and `return` statements.

---

## Statements vs Expressions

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STATEMENTS VS EXPRESSIONS                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   EXPRESSIONS produce values:                                               │
│     42              → value: 42                                             │
│     x + y           → value: sum                                            │
│     foo()           → value: return value                                   │
│                                                                              │
│   STATEMENTS perform actions:                                               │
│     const x = 5;    → declares variable (no value produced)                │
│     return x;       → exits function (no value produced)                    │
│     { ... }         → groups statements (no value produced)                 │
│                                                                              │
│   Statements end with semicolons. Expressions don't.                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Variable Declaration

```
const x: i32 = 42;
var y: i32 = 0;
```

Structure:
```
[const/var] [name] : [type] = [expression] ;
```

---

## parseVarDecl

```
function parseVarDecl():
    // We've already seen CONST or VAR
    is_const = (advance().type == KEYWORD_CONST)

    // Name
    name = expect(IDENTIFIER).lexeme

    // Type annotation
    expect(COLON)
    type_name = expect(IDENTIFIER).lexeme   // or TYPE_I32, etc.
    type = TypeExpr { name: type_name }

    // Initializer
    expect(EQUAL)
    value = parseExpression()

    // Semicolon
    expect(SEMICOLON)

    return VarDecl {
        name: name,
        type: type,
        value: value,
        is_const: is_const
    }
```

---

## Return Statement

```
return x + y;
return 42;
return;        // void return (optional value)
```

---

## parseReturnStmt

```
function parseReturnStmt():
    expect(KEYWORD_RETURN)

    // Check if there's a value
    if peek().type == SEMICOLON:
        value = null
    else:
        value = parseExpression()

    expect(SEMICOLON)

    return ReturnStmt {
        value: value
    }
```

---

## parseStatement

Dispatch to the right parser:

```
function parseStatement():
    token = peek()

    if token.type == KEYWORD_CONST or token.type == KEYWORD_VAR:
        return parseVarDecl()

    if token.type == KEYWORD_RETURN:
        return parseReturnStmt()

    error("Expected statement, got " + token.type)
```

---

## Visualized

```
Input: "const x: i32 = 42;"
Tokens: [CONST, IDENT("x"), COLON, TYPE_I32, EQUAL, NUMBER(42), SEMI, EOF]

parseStatement():
    peek() → CONST
    parseVarDecl():
        advance() → CONST (is_const = true)
        expect(IDENTIFIER) → "x"
        expect(COLON) → :
        expect(IDENTIFIER) → "i32"
        expect(EQUAL) → =
        parseExpression() → NumberExpr(42)
        expect(SEMICOLON) → ;
        return VarDecl { name: "x", type: i32, value: 42, is_const: true }

Result:
VarDecl {
    name: "x",
    type: TypeExpr { name: "i32" },
    value: NumberExpr { value: 42 },
    is_const: true
}
```

---

## Handling Type Keywords

In the lexer, we made `i32` a TYPE_I32 token. Update parseVarDecl:

```
function parseType():
    token = peek()

    if token.type == TYPE_I32:
        advance()
        return TypeExpr { name: "i32" }
    if token.type == TYPE_I64:
        advance()
        return TypeExpr { name: "i64" }
    if token.type == TYPE_BOOL:
        advance()
        return TypeExpr { name: "bool" }
    if token.type == TYPE_VOID:
        advance()
        return TypeExpr { name: "void" }
    if token.type == IDENTIFIER:
        // User-defined type
        advance()
        return TypeExpr { name: token.lexeme }

    error("Expected type")
```

---

## Verify Your Implementation

### Test 1: Const declaration
```
Input:  "const x: i32 = 42;"
AST:    VarDecl {
            name: "x",
            type: TypeExpr("i32"),
            value: NumberExpr(42),
            is_const: true
        }
```

### Test 2: Var declaration
```
Input:  "var count: i32 = 0;"
AST:    VarDecl {
            name: "count",
            type: TypeExpr("i32"),
            value: NumberExpr(0),
            is_const: false
        }
```

### Test 3: Expression value
```
Input:  "const sum: i32 = 1 + 2;"
AST:    VarDecl {
            name: "sum",
            type: TypeExpr("i32"),
            value: BinaryExpr(1, +, 2),
            is_const: true
        }
```

### Test 4: Return with value
```
Input:  "return 42;"
AST:    ReturnStmt {
            value: NumberExpr(42)
        }
```

### Test 5: Return expression
```
Input:  "return x + y;"
AST:    ReturnStmt {
            value: BinaryExpr(
                IdentifierExpr("x"),
                +,
                IdentifierExpr("y")
            )
        }
```

### Test 6: Missing semicolon
```
Input:  "const x: i32 = 42"
Result: Error - Expected SEMICOLON, got EOF
```

### Test 7: Missing type
```
Input:  "const x = 42;"
Result: Error - Expected COLON, got EQUAL
```

---

## Note on Type Inference

Some languages allow:
```
const x = 42;    // Type inferred as i32
```

We require explicit types for simplicity:
```
const x: i32 = 42;
```

You could add inference later in semantic analysis.

---

## What's Next

Let's group statements into blocks: `{ stmt; stmt; }`

Next: [Lesson 2.9: Blocks](../09-blocks/) →
