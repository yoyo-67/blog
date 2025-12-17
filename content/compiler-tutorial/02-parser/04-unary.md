---
title: "2.4: Unary Operators"
weight: 4
---

# Lesson 2.4: Unary Operators

Unary operators apply to a single operand: `-x`, `-42`.

---

## Goal

Parse negation (`-expr`) into UnaryExpr nodes.

---

## What Are Unary Operators?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          UNARY OPERATORS                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Unary = one operand (unlike binary which has two)                         │
│                                                                              │
│   -42       Negate a number                                                 │
│   -x        Negate a variable                                               │
│   -(a + b)  Negate an expression                                            │
│   --x       Negate a negation (double negative)                             │
│                                                                              │
│   The operator comes BEFORE the operand (prefix notation).                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The AST

```
-42

UnaryExpr {
    operator: MINUS,
    operand: NumberExpr { value: 42 }
}
```

```
-x

UnaryExpr {
    operator: MINUS,
    operand: IdentifierExpr { name: "x" }
}
```

```
--x

UnaryExpr {
    operator: MINUS,
    operand: UnaryExpr {
        operator: MINUS,
        operand: IdentifierExpr { name: "x" }
    }
}
```

---

## New Function: parseUnary

```
function parseUnary():
    // Check for unary operator
    if peek().type == MINUS:
        operator = advance()              // consume '-'
        operand = parseUnary()            // recursively parse operand
        return UnaryExpr {
            operator: operator,
            operand: operand
        }

    // No unary operator - fall through to atom
    return parseAtom()
```

---

## Why Recursive?

The operand of a unary operator can itself be a unary expression:

```
---x

parseUnary():
    MINUS → advance
    operand = parseUnary():
        MINUS → advance
        operand = parseUnary():
            MINUS → advance
            operand = parseUnary():
                x → IdentifierExpr
            return UnaryExpr(-x)
        return UnaryExpr(--x)
    return UnaryExpr(---x)
```

---

## Update parseExpression

```
function parseExpression():
    return parseUnary()      // Changed from parseAtom()
```

Now the call chain is:
```
parseExpression() → parseUnary() → parseAtom()
```

---

## Visualized

```
Input: "-42"
Tokens: [MINUS, NUMBER("42"), EOF]

parseExpression()
└── parseUnary()
    ├── peek() → MINUS? Yes
    ├── advance() → consumes '-'
    └── operand = parseUnary()
        └── parseAtom()
            └── NUMBER("42") → NumberExpr { value: 42 }
    └── return UnaryExpr { operator: MINUS, operand: NumberExpr{42} }

Result: UnaryExpr { operator: MINUS, operand: NumberExpr{42} }
```

---

## Precedence Preview

Unary operators bind tighter than binary operators:

```
-3 + 5

Should parse as: (-3) + 5
NOT as:          -(3 + 5)

Tree:
    Add
   /   \
 Neg    5
  |
  3
```

Our structure naturally handles this because `parseUnary` is called from within binary parsing (which we'll add next).

---

## Verify Your Implementation

### Test 1: Negate number
```
Input:  "-42"
Tokens: [MINUS, NUMBER("42"), EOF]
AST:    UnaryExpr {
            operator: MINUS,
            operand: NumberExpr { value: 42 }
        }
```

### Test 2: Negate identifier
```
Input:  "-x"
Tokens: [MINUS, IDENTIFIER("x"), EOF]
AST:    UnaryExpr {
            operator: MINUS,
            operand: IdentifierExpr { name: "x" }
        }
```

### Test 3: Double negative
```
Input:  "--x"
Tokens: [MINUS, MINUS, IDENTIFIER("x"), EOF]
AST:    UnaryExpr {
            operator: MINUS,
            operand: UnaryExpr {
                operator: MINUS,
                operand: IdentifierExpr { name: "x" }
            }
        }
```

### Test 4: Negate grouped expression
```
Input:  "-(42)"
Tokens: [MINUS, LPAREN, NUMBER("42"), RPAREN, EOF]
AST:    UnaryExpr {
            operator: MINUS,
            operand: NumberExpr { value: 42 }
        }
```

### Test 5: Plain number (no negation)
```
Input:  "42"
Tokens: [NUMBER("42"), EOF]
AST:    NumberExpr { value: 42 }
```

---

## Extension: Other Unary Operators

You could add more unary operators:

```
function parseUnary():
    if peek().type == MINUS:
        // ... negation
    if peek().type == BANG:     // !
        // ... logical not
    if peek().type == TILDE:    // ~
        // ... bitwise not

    return parseAtom()
```

For our mini compiler, we only need `-`.

---

## What's Next

Now for the big one: binary operators like `a + b`.

Next: [Lesson 2.5: Binary Operators (Simple)](../05-binary-simple/) →
