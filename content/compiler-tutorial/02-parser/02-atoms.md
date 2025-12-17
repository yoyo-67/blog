---
title: "2.2: Atoms"
weight: 2
---

# Lesson 2.2: Parsing Atoms

Atoms are the simplest expressions: numbers and identifiers.

---

## Goal

Parse NUMBER and IDENTIFIER tokens into AST nodes.

---

## What Are Atoms?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              ATOMS                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Atoms are expressions that don't contain other expressions.               │
│                                                                              │
│   ✓ 42          Number literal                                              │
│   ✓ foo         Identifier                                                  │
│   ✓ x           Single-letter identifier                                    │
│                                                                              │
│   ✗ 3 + 5       Contains sub-expressions                                   │
│   ✗ -x          Contains sub-expression                                     │
│                                                                              │
│   Atoms are the "leaves" of the expression tree.                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Parser State

First, set up your parser structure:

```
Parser {
    tokens: Token[]        // From lexer
    pos: integer           // Current position (starts at 0)

    // Helper functions
    peek() → Token         // Current token without advancing
    advance() → Token      // Return current, move to next
    isAtEnd() → boolean    // Are we at EOF?
}
```

---

## Helper Functions

```
function peek():
    return tokens[pos]

function advance():
    token = tokens[pos]
    pos = pos + 1
    return token

function isAtEnd():
    return peek().type == EOF

function expect(type):
    if peek().type != type:
        error("Expected " + type + ", got " + peek().type)
    return advance()
```

---

## The parseAtom Function

```
function parseAtom():
    token = peek()

    if token.type == NUMBER:
        advance()
        return NumberExpr {
            value: parseInteger(token.lexeme)
        }

    if token.type == IDENTIFIER:
        advance()
        return IdentifierExpr {
            name: token.lexeme
        }

    error("Expected expression, got " + token.type)
```

---

## Visualized

```
Input tokens: [NUMBER("42"), EOF]

parseAtom():
    peek() → NUMBER("42")
    Is NUMBER? Yes!
    advance() → NUMBER("42")
    return NumberExpr { value: 42 }

Result: NumberExpr { value: 42 }
```

```
Input tokens: [IDENTIFIER("foo"), EOF]

parseAtom():
    peek() → IDENTIFIER("foo")
    Is NUMBER? No
    Is IDENTIFIER? Yes!
    advance() → IDENTIFIER("foo")
    return IdentifierExpr { name: "foo" }

Result: IdentifierExpr { name: "foo" }
```

---

## Top-Level Parse Function

For now, our parser just parses a single expression:

```
function parse(tokens):
    parser = Parser { tokens: tokens, pos: 0 }
    expr = parseAtom()
    expect(EOF)  // Ensure we consumed everything
    return expr
```

---

## Verify Your Implementation

### Test 1: Number
```
Input:  "42"
Tokens: [NUMBER("42"), EOF]
AST:    NumberExpr { value: 42 }
```

### Test 2: Identifier
```
Input:  "foo"
Tokens: [IDENTIFIER("foo"), EOF]
AST:    IdentifierExpr { name: "foo" }
```

### Test 3: Single letter
```
Input:  "x"
Tokens: [IDENTIFIER("x"), EOF]
AST:    IdentifierExpr { name: "x" }
```

### Test 4: Zero
```
Input:  "0"
Tokens: [NUMBER("0"), EOF]
AST:    NumberExpr { value: 0 }
```

### Test 5: Error case
```
Input:  "+"
Tokens: [PLUS, EOF]
Result: Error - Expected expression, got PLUS
```

---

## Integration Test

Chain lexer and parser together:

```
function compile(source):
    tokens = tokenize(source)
    ast = parse(tokens)
    return ast

test:
    ast = compile("42")
    assert ast.type == NumberExpr
    assert ast.value == 42
```

---

## What's Next

Let's handle parenthesized expressions like `(3 + 5)`.

Next: [Lesson 2.3: Grouping](../03-grouping/) →
