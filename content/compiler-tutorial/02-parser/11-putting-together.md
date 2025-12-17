---
title: "2.11: Complete Parser"
weight: 11
---

# Lesson 2.11: Putting It All Together

Let's assemble all the pieces into a complete, working parser.

---

## Goal

Create a `parse(tokens)` function that transforms tokens into a complete AST.

---

## Complete Parser Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         COMPLETE PARSER                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Parser {                                                                   │
│       tokens: Token[]                                                        │
│       pos: integer                                                           │
│                                                                              │
│       // Helpers                                                             │
│       peek() → Token                                                         │
│       advance() → Token                                                      │
│       expect(type) → Token                                                   │
│       isAtEnd() → boolean                                                    │
│                                                                              │
│       // Expressions                                                         │
│       parseExpression(minPrec) → Expr                                       │
│       parseUnary() → Expr                                                   │
│       parseAtom() → Expr                                                    │
│                                                                              │
│       // Types                                                               │
│       parseType() → TypeExpr                                                │
│                                                                              │
│       // Statements                                                          │
│       parseStatement() → Stmt                                               │
│       parseVarDecl() → VarDecl                                              │
│       parseReturnStmt() → ReturnStmt                                        │
│       parseBlock() → Block                                                  │
│                                                                              │
│       // Declarations                                                        │
│       parseFunction() → FnDecl                                              │
│       parseParamList() → Parameter[]                                        │
│       parseParam() → Parameter                                              │
│                                                                              │
│       // Entry point                                                         │
│       parseProgram() → Root                                                 │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Call Hierarchy

```
parseProgram()
└── parseFunction()
    ├── parseParamList()
    │   └── parseParam()
    │       └── parseType()
    ├── parseType()
    └── parseBlock()
        └── parseStatement()
            ├── parseVarDecl()
            │   ├── parseType()
            │   └── parseExpression()
            ├── parseReturnStmt()
            │   └── parseExpression()
            └── parseBlock() (nested)

parseExpression()
└── parseUnary()
    └── parseAtom()
        └── parseExpression() (for grouping)
```

---

## Complete Code Summary

### Helper Functions
```
function peek():
    return tokens[pos]

function advance():
    token = tokens[pos]
    pos = pos + 1
    return token

function expect(type):
    if peek().type != type:
        error("Expected " + type + ", got " + peek().type)
    return advance()

function isAtEnd():
    return peek().type == EOF
```

### Binding Power
```
function getBindingPower(tokenType):
    switch tokenType:
        PLUS, MINUS:  return 1
        STAR, SLASH:  return 2
        default:      return 0
```

### Expression Parsing
```
function parseExpression(minPrecedence = 0):
    left = parseUnary()
    while getBindingPower(peek().type) >= minPrecedence:
        op = advance()
        right = parseExpression(getBindingPower(op.type) + 1)
        left = BinaryExpr { left, op, right }
    return left

function parseUnary():
    if peek().type == MINUS:
        op = advance()
        return UnaryExpr { op, parseUnary() }
    return parseAtom()

function parseAtom():
    token = peek()
    if token.type == NUMBER:
        advance()
        return NumberExpr { value: parseInt(token.lexeme) }
    if token.type == IDENTIFIER:
        advance()
        return IdentifierExpr { name: token.lexeme }
    if token.type == LPAREN:
        advance()
        expr = parseExpression()
        expect(RPAREN)
        return expr
    error("Expected expression")
```

### Type Parsing
```
function parseType():
    token = peek()
    if token.type in [TYPE_I32, TYPE_I64, TYPE_BOOL, TYPE_VOID]:
        advance()
        return TypeExpr { name: tokenTypeToString(token.type) }
    if token.type == IDENTIFIER:
        advance()
        return TypeExpr { name: token.lexeme }
    error("Expected type")
```

### Statement Parsing
```
function parseStatement():
    if peek().type in [KEYWORD_CONST, KEYWORD_VAR]:
        return parseVarDecl()
    if peek().type == KEYWORD_RETURN:
        return parseReturnStmt()
    if peek().type == LBRACE:
        return parseBlock()
    error("Expected statement")

function parseVarDecl():
    is_const = (advance().type == KEYWORD_CONST)
    name = expect(IDENTIFIER).lexeme
    expect(COLON)
    type = parseType()
    expect(EQUAL)
    value = parseExpression()
    expect(SEMICOLON)
    return VarDecl { name, type, value, is_const }

function parseReturnStmt():
    expect(KEYWORD_RETURN)
    value = null
    if peek().type != SEMICOLON:
        value = parseExpression()
    expect(SEMICOLON)
    return ReturnStmt { value }

function parseBlock():
    expect(LBRACE)
    statements = []
    while peek().type != RBRACE and not isAtEnd():
        statements.append(parseStatement())
    expect(RBRACE)
    return Block { statements }
```

### Declaration Parsing
```
function parseFunction():
    expect(KEYWORD_FN)
    name = expect(IDENTIFIER).lexeme
    expect(LPAREN)
    params = parseParamList()
    expect(RPAREN)
    return_type = parseType()
    body = parseBlock()
    return FnDecl { name, params, return_type, body }

function parseParamList():
    params = []
    if peek().type == RPAREN:
        return params
    params.append(parseParam())
    while peek().type == COMMA:
        advance()
        params.append(parseParam())
    return params

function parseParam():
    name = expect(IDENTIFIER).lexeme
    expect(COLON)
    type = parseType()
    return Parameter { name, type }

function parseProgram():
    declarations = []
    while not isAtEnd():
        declarations.append(parseFunction())
    return Root { declarations }
```

### Entry Point
```
function parse(tokens):
    parser = Parser { tokens: tokens, pos: 0 }
    return parser.parseProgram()
```

---

## Full Test Suite

### Test 1: Empty program
```
Input:  ""
Tokens: [EOF]
AST:    Root { declarations: [] }
```

### Test 2: Minimal function
```
Input:  "fn main() i32 { return 0; }"
AST:    Root {
            declarations: [
                FnDecl {
                    name: "main",
                    params: [],
                    return_type: i32,
                    body: Block {
                        statements: [
                            ReturnStmt { value: NumberExpr(0) }
                        ]
                    }
                }
            ]
        }
```

### Test 3: Function with expression
```
Input:  "fn calc() i32 { return 1 + 2 * 3; }"
AST:    Root {
            declarations: [
                FnDecl {
                    name: "calc",
                    params: [],
                    return_type: i32,
                    body: Block {
                        statements: [
                            ReturnStmt {
                                value: BinaryExpr(
                                    1, +, BinaryExpr(2, *, 3)
                                )
                            }
                        ]
                    }
                }
            ]
        }
```

### Test 4: Function with parameters
```
Input:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

AST verified: params contains two parameters, body returns binary expression
```

### Test 5: Function with locals
```
Input:
fn compute() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    return x + y;
}

AST verified: body contains two VarDecl and one ReturnStmt
```

### Test 6: Multiple functions
```
Input:
fn square(x: i32) i32 { return x * x; }
fn main() i32 { return 0; }

AST verified: Root.declarations has two FnDecl
```

### Test 7: Complex program
```
Input:
fn add(a: i32, b: i32) i32 {
    const result: i32 = a + b;
    return result;
}

fn main() i32 {
    return 0;
}

Expected AST structure verified
```

---

## Integration: Lexer + Parser

```
function compile(source):
    tokens = tokenize(source)
    ast = parse(tokens)
    return ast

// Test
source = "fn main() i32 { return 42; }"
ast = compile(source)
assert ast.declarations[0].name == "main"
assert ast.declarations[0].body.statements[0].value.value == 42
```

---

## Error Handling Tips

1. **Synchronization**: After an error, skip to the next statement or declaration
2. **Multiple errors**: Don't stop at the first error; collect them all
3. **Context**: Include line/column in error messages
4. **Recovery**: Try to parse as much as possible even with errors

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         PARSER SUMMARY                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. AST NODES       Define node types for the tree                         │
│   2. ATOMS           Numbers, identifiers                                   │
│   3. GROUPING        Parenthesized expressions                              │
│   4. UNARY           Negation: -x                                           │
│   5. BINARY          a + b, a * b                                           │
│   6. PRECEDENCE      Why * beats +                                          │
│   7. PREC IMPL       Precedence climbing algorithm                          │
│   8. STATEMENTS      const, var, return                                     │
│   9. BLOCKS          { stmt; stmt; }                                        │
│  10. FUNCTIONS       fn name(params) type { body }                          │
│  11. INTEGRATION     Complete parser                                        │
│                                                                              │
│   Lines of code: ~150-200 depending on language                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

We have tokens (lexer) and a tree (parser). Now we need to transform this tree into a simpler representation for analysis and code generation.

Next: [Section 3: ZIR (Intermediate Representation)](../../03-zir/) →
