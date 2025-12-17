---
title: "2.3: Grouping"
weight: 3
---

# Lesson 2.3: Parenthesized Expressions

Parentheses group expressions: `(3 + 5)`.

---

## Goal

Parse `(expression)` into an AST, handling the parentheses as grouping.

---

## Key Insight

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         GROUPING INSIGHT                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Parentheses don't create a new node type!                                 │
│                                                                              │
│   Source: (42)                                                              │
│   AST:    NumberExpr { value: 42 }     ← Just the inner expression         │
│                                                                              │
│   Source: (3 + 5)                                                           │
│   AST:    BinaryExpr { ... }           ← Just the inner expression         │
│                                                                              │
│   The parentheses are "consumed" during parsing.                            │
│   They affect HOW we parse, not WHAT we produce.                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Updated parseAtom

Add a case for `LPAREN`:

```
function parseAtom():
    token = peek()

    if token.type == NUMBER:
        advance()
        return NumberExpr { value: parseInteger(token.lexeme) }

    if token.type == IDENTIFIER:
        advance()
        return IdentifierExpr { name: token.lexeme }

    if token.type == LPAREN:                     // ← ADD THIS
        advance()                                 // consume '('
        expr = parseExpression()                  // parse inside
        expect(RPAREN)                            // consume ')'
        return expr                               // return inner expr

    error("Expected expression, got " + token.type)
```

---

## Wait - parseExpression?

We're calling `parseExpression()` which we haven't written yet!

For now, make it just call `parseAtom()`:

```
function parseExpression():
    return parseAtom()      // We'll expand this soon
```

This creates mutual recursion:
- `parseAtom` calls `parseExpression` for grouped expressions
- `parseExpression` calls `parseAtom` for simple expressions

---

## Visualized

```
Input tokens: [LPAREN, NUMBER("42"), RPAREN, EOF]

parseAtom():
    peek() → LPAREN
    Is NUMBER? No
    Is IDENTIFIER? No
    Is LPAREN? Yes!
    advance()                      → consumes '('
    expr = parseExpression()
        → parseAtom()
        → peek() → NUMBER("42")
        → return NumberExpr { value: 42 }
    expect(RPAREN)                 → consumes ')'
    return NumberExpr { value: 42 }

Result: NumberExpr { value: 42 }
```

---

## Nested Parentheses

```
Input: ((42))

Tokens: [LPAREN, LPAREN, NUMBER("42"), RPAREN, RPAREN, EOF]

parseAtom():
    LPAREN → advance
    parseExpression() → parseAtom():
        LPAREN → advance
        parseExpression() → parseAtom():
            NUMBER("42") → NumberExpr { value: 42 }
        expect(RPAREN) ✓
        return NumberExpr { value: 42 }
    expect(RPAREN) ✓
    return NumberExpr { value: 42 }

Result: NumberExpr { value: 42 }
```

The nesting is handled naturally by recursion!

---

## Verify Your Implementation

### Test 1: Simple grouping
```
Input:  "(42)"
Tokens: [LPAREN, NUMBER("42"), RPAREN, EOF]
AST:    NumberExpr { value: 42 }
```

### Test 2: Grouped identifier
```
Input:  "(foo)"
Tokens: [LPAREN, IDENTIFIER("foo"), RPAREN, EOF]
AST:    IdentifierExpr { name: "foo" }
```

### Test 3: Nested grouping
```
Input:  "((42))"
Tokens: [LPAREN, LPAREN, NUMBER("42"), RPAREN, RPAREN, EOF]
AST:    NumberExpr { value: 42 }
```

### Test 4: Missing close paren
```
Input:  "(42"
Tokens: [LPAREN, NUMBER("42"), EOF]
Result: Error - Expected RPAREN, got EOF
```

### Test 5: Extra close paren
```
Input:  "(42))"
Tokens: [LPAREN, NUMBER("42"), RPAREN, RPAREN, EOF]
Result: Error - Expected EOF, got RPAREN
```

---

## Error Messages

Good error messages help users:

```
// Instead of:
error("Expected RPAREN")

// Better:
error("Unclosed parenthesis - expected ')' at line " + line)
```

---

## What's Next

Let's handle unary operators like `-x`.

Next: [Lesson 2.4: Unary](../04-unary/) →
