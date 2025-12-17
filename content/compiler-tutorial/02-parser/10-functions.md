---
title: "2.10: Functions"
weight: 10
---

# Lesson 2.10: Function Declarations

Functions are the building blocks of programs.

---

## Goal

Parse `fn name(params) return_type { body }` into FnDecl nodes.

---

## Function Syntax

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

Structure:
```
fn [name] ( [params] ) [return_type] { [body] }
```

---

## Function AST

```
FnDecl {
    name: string,
    params: Parameter[],
    return_type: TypeExpr,
    body: Block
}

Parameter {
    name: string,
    type: TypeExpr
}
```

---

## parseFunction

```
function parseFunction():
    expect(KEYWORD_FN)

    // Function name
    name = expect(IDENTIFIER).lexeme

    // Parameters
    expect(LPAREN)
    params = parseParamList()
    expect(RPAREN)

    // Return type
    return_type = parseType()

    // Body
    body = parseBlock()

    return FnDecl {
        name: name,
        params: params,
        return_type: return_type,
        body: body
    }
```

---

## parseParamList

```
function parseParamList():
    params = []

    // Empty parameter list
    if peek().type == RPAREN:
        return params

    // First parameter
    params.append(parseParam())

    // Additional parameters
    while peek().type == COMMA:
        advance()   // consume comma
        params.append(parseParam())

    return params
```

---

## parseParam

```
function parseParam():
    name = expect(IDENTIFIER).lexeme
    expect(COLON)
    type = parseType()

    return Parameter {
        name: name,
        type: type
    }
```

---

## Full Trace

```
Input: "fn add(a: i32, b: i32) i32 { return a + b; }"

Tokens: [FN, IDENT("add"), LPAREN, IDENT("a"), COLON, TYPE_I32,
         COMMA, IDENT("b"), COLON, TYPE_I32, RPAREN, TYPE_I32,
         LBRACE, RETURN, IDENT("a"), PLUS, IDENT("b"), SEMI, RBRACE, EOF]

parseFunction():
    expect(FN) ✓
    name = expect(IDENT) → "add"
    expect(LPAREN) ✓

    parseParamList():
        peek() → IDENT("a"), not RPAREN

        parseParam():
            name = "a"
            expect(COLON) ✓
            type = parseType() → i32
            return Parameter { name: "a", type: i32 }

        params = [Parameter("a", i32)]

        peek() → COMMA
        advance() → consume COMMA

        parseParam():
            name = "b"
            expect(COLON) ✓
            type = parseType() → i32
            return Parameter { name: "b", type: i32 }

        params = [Parameter("a", i32), Parameter("b", i32)]

        peek() → RPAREN, not COMMA
        return params

    expect(RPAREN) ✓
    return_type = parseType() → i32

    body = parseBlock():
        expect(LBRACE) ✓
        parseStatement() → ReturnStmt { value: BinaryExpr(a, +, b) }
        expect(RBRACE) ✓
        return Block { statements: [ReturnStmt] }

    return FnDecl {
        name: "add",
        params: [Parameter("a", i32), Parameter("b", i32)],
        return_type: i32,
        body: Block { [ReturnStmt { BinaryExpr(a, +, b) }] }
    }
```

---

## The Root Node

A program is a list of function declarations:

```
function parseProgram():
    declarations = []

    while not isAtEnd():
        if peek().type == KEYWORD_FN:
            declarations.append(parseFunction())
        else:
            error("Expected function declaration")

    return Root {
        declarations: declarations
    }
```

---

## Verify Your Implementation

### Test 1: Simple function
```
Input:  "fn main() i32 { return 0; }"
AST:    FnDecl {
            name: "main",
            params: [],
            return_type: i32,
            body: Block {
                statements: [ReturnStmt { value: NumberExpr(0) }]
            }
        }
```

### Test 2: Function with parameters
```
Input:  "fn add(a: i32, b: i32) i32 { return a + b; }"
AST:    FnDecl {
            name: "add",
            params: [
                Parameter { name: "a", type: i32 },
                Parameter { name: "b", type: i32 }
            ],
            return_type: i32,
            body: Block {
                statements: [ReturnStmt { BinaryExpr(a, +, b) }]
            }
        }
```

### Test 3: Single parameter
```
Input:  "fn square(x: i32) i32 { return x * x; }"
AST:    FnDecl {
            name: "square",
            params: [Parameter { name: "x", type: i32 }],
            return_type: i32,
            body: Block {
                statements: [ReturnStmt { BinaryExpr(x, *, x) }]
            }
        }
```

### Test 4: Void return
```
Input:  "fn doNothing() void { }"
AST:    FnDecl {
            name: "doNothing",
            params: [],
            return_type: void,
            body: Block { statements: [] }
        }
```

### Test 5: Multiple functions
```
Input:  "fn foo() i32 { return 1; } fn bar() i32 { return 2; }"
AST:    Root {
            declarations: [
                FnDecl { name: "foo", ... },
                FnDecl { name: "bar", ... }
            ]
        }
```

### Test 6: Function with local variables
```
Input:  "fn calc() i32 { const x: i32 = 5; return x * 2; }"
AST:    FnDecl {
            name: "calc",
            params: [],
            return_type: i32,
            body: Block {
                statements: [
                    VarDecl { name: "x", value: 5 },
                    ReturnStmt { BinaryExpr(x, *, 2) }
                ]
            }
        }
```

---

## Error Cases

### Missing function name
```
Input:  "fn () i32 { }"
Result: Error - Expected IDENTIFIER, got LPAREN
```

### Missing return type
```
Input:  "fn foo() { }"
Result: Error - Expected type, got LBRACE
```

### Missing body
```
Input:  "fn foo() i32"
Result: Error - Expected LBRACE, got EOF
```

---

## What's Next

Let's put everything together into a complete parser.

Next: [Lesson 2.11: Complete Parser](../11-putting-together/) →
