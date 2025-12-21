---
title: "2.7: Complete Parser"
weight: 7
---

# Lesson 2.7: Complete Parser

Put everything together with the full grammar, implementation, and patterns.

---

## Goal

Consolidate all lessons into a complete parser with reusable patterns.

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

## Grammar Rules → Parse Functions

Each grammar rule maps to one parse function:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                  GRAMMAR RULES → PARSE FUNCTIONS                             │
├────────────────────────────────┬─────────────────────────────────────────────┤
│  Grammar Rule                  │  Parse Function                             │
├────────────────────────────────┼─────────────────────────────────────────────┤
│  program → function*           │  parseProgram()                             │
│  function → "fn" NAME ...      │  parseFunction()                            │
│  parameters → param (, param)* │  parseParameters()                          │
│  parameter → NAME ":" type     │  parseParameter()                           │
│  type → "i32" | "bool" | ...   │  parseType()                                │
│  block → "{" statement* "}"    │  parseBlock()                               │
│  statement → var | return      │  parseStatement()                           │
│  var_decl → "const" NAME ...   │  parseVarDecl()                             │
│  return_stmt → "return" ...    │  parseReturnStmt()                          │
│  expression → term ((+|-) ..)* │  parseExpression()                          │
│  term → unary ((*|/) unary)*   │  parseTerm()                                │
│  unary → "-" unary | primary   │  parseUnary()                               │
│  primary → NUM | ID | (expr)   │  parsePrimary()                             │
└────────────────────────────────┴─────────────────────────────────────────────┘
```

---

## Grammar Notation → Code Pattern

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     GRAMMAR NOTATION → CODE PATTERN                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Grammar notation          Code pattern                                    │
│   ────────────────          ────────────                                    │
│                                                                              │
│   "keyword"                 expect(KEYWORD) or consume(KEYWORD)             │
│                                                                              │
│   TOKEN                     consume(TOKEN) and use its value                │
│                                                                              │
│   rule                      call parseRule()                                │
│                                                                              │
│   A | B                     if see(A): parseA() else: parseB()              │
│                                                                              │
│   A*                        while see(A): parseA()                          │
│                                                                              │
│   A?                        if see(A): parseA()                             │
│                                                                              │
│   (A B)*                    while see(A): parseA(); parseB()                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Common Patterns

Here are patterns you'll use over and over:

### Binary Operators (Left-Associative)

```
Grammar:  rule → next_level ((OP1 | OP2) next_level)*

Code:
function parseRule():
    left = parseNextLevel()
    while see(OP1) or see(OP2):
        op = consume()
        right = parseNextLevel()
        left = BinaryNode(left, op, right)
    return left
```

### Unary Operators (Prefix)

```
Grammar:  rule → OP rule | next_level

Code:
function parseRule():
    if see(OP):
        consume()
        operand = parseRule()    // recursive
        return UnaryNode(OP, operand)
    return parseNextLevel()
```

### Optional Parts

```
Grammar:  rule → A B?

Code:
function parseRule():
    a = parseA()
    b = null
    if see(B_START):
        b = parseB()
    return Node(a, b)
```

### Lists with Separators

```
Grammar:  list → item ("," item)*

Code:
function parseList():
    items = [parseItem()]
    while see(COMMA):
        consume(COMMA)
        items.append(parseItem())
    return items
```

### Blocks of Things

```
Grammar:  block → "{" item* "}"

Code:
function parseBlock():
    expect(LBRACE)
    items = []
    while not see(RBRACE):
        items.append(parseItem())
    expect(RBRACE)
    return items
```

---

## Complete Parser Pseudocode

```
// Parser state
tokens: Token[]
pos: integer = 0

// Helper functions
function peek(): Token
    return tokens[pos]

function advance(): Token
    token = tokens[pos]
    pos = pos + 1
    return token

function see(type): boolean
    return peek().type == type

function expect(type): Token
    if not see(type):
        error("Expected " + type)
    return advance()

// ─────────────────────────────────────────────────────────────
// PROGRAM
// ─────────────────────────────────────────────────────────────

function parseProgram():
    functions = []
    while not see(EOF):
        functions.append(parseFunction())
    return ProgramNode(functions)

// ─────────────────────────────────────────────────────────────
// FUNCTIONS
// ─────────────────────────────────────────────────────────────

function parseFunction():
    expect(FN)
    name = expect(IDENTIFIER).lexeme
    expect(LPAREN)

    params = []
    if not see(RPAREN):
        params = parseParameters()

    expect(RPAREN)
    body = parseBlock()

    return FunctionNode(name, params, body)

function parseParameters():
    params = []
    params.append(parseParameter())

    while see(COMMA):
        advance()
        params.append(parseParameter())

    return params

function parseParameter():
    name = expect(IDENTIFIER).lexeme
    expect(COLON)
    type = parseType()
    return ParameterNode(name, type)

function parseType():
    if see(I32):
        advance()
        return "i32"
    if see(BOOL):
        advance()
        return "bool"
    if see(VOID):
        advance()
        return "void"
    error("Expected type")

// ─────────────────────────────────────────────────────────────
// STATEMENTS
// ─────────────────────────────────────────────────────────────

function parseBlock():
    expect(LBRACE)

    statements = []
    while not see(RBRACE):
        statements.append(parseStatement())

    expect(RBRACE)
    return BlockNode(statements)

function parseStatement():
    if see(CONST):
        return parseVarDecl()
    if see(RETURN):
        return parseReturnStmt()
    error("Expected statement")

function parseVarDecl():
    expect(CONST)
    name = expect(IDENTIFIER).lexeme
    expect(EQUAL)
    value = parseExpression()
    expect(SEMICOLON)
    return VarDeclNode(name, value)

function parseReturnStmt():
    expect(RETURN)
    value = parseExpression()
    expect(SEMICOLON)
    return ReturnStmtNode(value)

// ─────────────────────────────────────────────────────────────
// EXPRESSIONS
// ─────────────────────────────────────────────────────────────

function parseExpression():
    left = parseTerm()

    while see(PLUS) or see(MINUS):
        op = advance()
        right = parseTerm()
        if op.type == PLUS:
            left = AddNode(left, right)
        else:
            left = SubNode(left, right)

    return left

function parseTerm():
    left = parseUnary()

    while see(STAR) or see(SLASH):
        op = advance()
        right = parseUnary()
        if op.type == STAR:
            left = MulNode(left, right)
        else:
            left = DivNode(left, right)

    return left

function parseUnary():
    if see(MINUS):
        advance()
        operand = parseUnary()
        return NegateNode(operand)
    return parsePrimary()

function parsePrimary():
    if see(NUMBER):
        token = advance()
        return NumberNode(parseInt(token.lexeme))

    if see(IDENTIFIER):
        token = advance()
        return IdentifierNode(token.lexeme)

    if see(LPAREN):
        advance()
        expr = parseExpression()
        expect(RPAREN)
        return expr

    error("Expected expression")
```

---

## The Key Insights

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          THE KEY INSIGHTS                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. GRAMMAR STRUCTURE = AST STRUCTURE                                      │
│   ─────────────────────────────────────                                      │
│   The nesting in your grammar rules becomes the nesting in your tree.       │
│   If rule A calls rule B, then A nodes contain B nodes as children.         │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   2. NESTING DEPTH = PRECEDENCE                                             │
│   ─────────────────────────────                                              │
│   Rules that are called first (deepest in the call chain) have the          │
│   highest precedence. They're evaluated first because they're innermost.    │
│                                                                              │
│   expression → term → unary → primary                                       │
│   LOW prec    ───────────────►    HIGH prec                                 │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   3. CALL STACK = TREE STRUCTURE                                            │
│   ──────────────────────────────                                             │
│   As parse functions call each other, the call stack naturally forms        │
│   the tree structure. When functions return, they return tree nodes         │
│   to their parent callers.                                                   │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   4. EACH RULE = ONE FUNCTION                                               │
│   ───────────────────────────                                                │
│   There's a direct 1:1 mapping from grammar rules to parse functions.       │
│   Write the grammar first, then translating to code is mechanical.          │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   5. LOOPS FOR *, CONDITIONALS FOR |                                        │
│   ────────────────────────────────────                                       │
│   The * becomes a while loop. The | becomes an if-else chain.               │
│   The ? becomes a simple if check.                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Extending the Grammar

Once you understand the pattern, adding new features is straightforward.

### Adding If Statements

```
statement → var_decl
          | return_stmt
          | if_stmt            ← NEW

if_stmt → "if" expression block ("else" block)?
```

```
function parseIfStmt():
    expect(IF)
    condition = parseExpression()
    then_block = parseBlock()

    else_block = null
    if see(ELSE):
        advance()
        else_block = parseBlock()

    return IfNode(condition, then_block, else_block)
```

### Adding While Loops

```
statement → var_decl
          | return_stmt
          | if_stmt
          | while_stmt         ← NEW

while_stmt → "while" expression block
```

```
function parseWhileStmt():
    expect(WHILE)
    condition = parseExpression()
    body = parseBlock()
    return WhileNode(condition, body)
```

### Adding More Operators

To add comparison operators (`<`, `>`, `==`) with correct precedence:

```
expression  → comparison                                    ← LOWEST
comparison  → additive (("<" | ">" | "==") additive)*      ← LOW
additive    → term (("+" | "-") term)*                     ← MEDIUM
term        → unary (("*" | "/") unary)*                   ← HIGH
unary       → "-" unary | primary                          ← HIGHER
primary     → NUMBER | IDENTIFIER | "(" expression ")"     ← HIGHEST
```

The pattern: **insert new rules between existing ones** based on where you want the precedence.

---

## The Grammar Design Process

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE GRAMMAR DESIGN PROCESS                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   STEP 1: Write example programs                                            │
│   ──────────────────────────────                                             │
│   What should your language look like? Write examples:                      │
│                                                                              │
│       1 + 2                                                                 │
│       const x = 5;                                                          │
│       fn add(a, b) { return a + b; }                                        │
│                                                                              │
│   STEP 2: Identify categories                                               │
│   ──────────────────────────                                                 │
│   What kinds of things exist?                                               │
│                                                                              │
│       - Expressions (produce values)                                        │
│       - Statements (do things)                                              │
│       - Declarations (define things)                                        │
│                                                                              │
│   STEP 3: List operators by precedence                                      │
│   ────────────────────────────────────                                       │
│   From lowest to highest:                                                   │
│                                                                              │
│       1. || (or)                                                            │
│       2. && (and)                                                           │
│       3. == != < > (comparison)                                             │
│       4. + - (additive)                                                     │
│       5. * / (multiplicative)                                               │
│       6. - ! (unary prefix)                                                 │
│       7. () . [] (postfix)                                                  │
│                                                                              │
│   STEP 4: Write rules from bottom up                                        │
│   ──────────────────────────────────                                         │
│   Start with the HIGHEST precedence (primary),                              │
│   then work your way up to the LOWEST (expression).                         │
│                                                                              │
│   STEP 5: Add statements and declarations                                   │
│   ────────────────────────────────────────                                   │
│   Statements contain expressions.                                           │
│   Declarations contain statements (in blocks).                              │
│   Program contains declarations.                                            │
│                                                                              │
│   STEP 6: Translate to parse functions                                      │
│   ────────────────────────────────────                                       │
│   One rule = one function.                                                  │
│   Follow the mechanical translation.                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Full Program Example

Here's what our grammar can parse:

```
fn factorial(n: i32) {
    const result = n * (n - 1);
    return result;
}

fn main() {
    const x = 5;
    return x;
}
```

AST produced:

```
ProgramNode {
    functions: [
        FunctionNode {
            name: "factorial",
            params: [ParameterNode { name: "n", type: "i32" }],
            body: BlockNode {
                statements: [
                    VarDeclNode {
                        name: "result",
                        value: MulNode {
                            left: IdentifierNode("n"),
                            right: SubNode {
                                left: IdentifierNode("n"),
                                right: NumberNode(1)
                            }
                        }
                    },
                    ReturnStmtNode {
                        value: IdentifierNode("result")
                    }
                ]
            }
        },
        FunctionNode {
            name: "main",
            params: [],
            body: BlockNode {
                statements: [
                    VarDeclNode { name: "x", value: NumberNode(5) },
                    ReturnStmtNode { value: IdentifierNode("x") }
                ]
            }
        }
    ]
}
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   WHAT WE LEARNED:                                                           │
│                                                                              │
│   1. Grammar defines the structure of valid programs                        │
│   2. Each grammar rule → one parse function                                 │
│   3. Precedence is achieved through multiple levels                         │
│   4. The call stack mirrors the tree structure                              │
│   5. Patterns: * → while, | → if-else, ? → if                              │
│                                                                              │
│   THE GRAMMAR:                                                               │
│                                                                              │
│   program     → function*                                                   │
│   function    → "fn" IDENTIFIER "(" parameters? ")" block                   │
│   parameters  → parameter ("," parameter)*                                  │
│   parameter   → IDENTIFIER ":" type                                         │
│   block       → "{" statement* "}"                                          │
│   statement   → var_decl | return_stmt                                      │
│   var_decl    → "const" IDENTIFIER "=" expression ";"                       │
│   return_stmt → "return" expression ";"                                     │
│   expression  → term (("+" | "-") term)*                                    │
│   term        → unary (("*" | "/") unary)*                                  │
│   unary       → "-" unary | primary                                         │
│   primary     → NUMBER | IDENTIFIER | "(" expression ")"                    │
│                                                                              │
│   NOW YOU CAN:                                                               │
│                                                                              │
│   - Parse expressions with correct precedence                               │
│   - Parse statements and declarations                                       │
│   - Parse complete programs with functions                                  │
│   - Extend the grammar with new features                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

With the parser complete, we have an AST representing our program. Next, we'll analyze this tree for semantic correctness and then generate code.

Next: [Section 3: Semantic Analysis](../../03-semantic/) →
