---
title: "1.6: Identifiers"
weight: 6
---

# Lesson 1.6: Identifiers

Identifiers are names for variables, functions, and types: `foo`, `bar123`, `_temp`.

---

## Goal

Recognize sequences of letters, digits, and underscores (starting with a letter or underscore) as IDENTIFIER tokens.

---

## The Rules

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          IDENTIFIER RULES                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   VALID identifiers:                                                        │
│     foo        (letters only)                                               │
│     bar123     (letters followed by digits)                                 │
│     _temp      (starts with underscore)                                     │
│     camelCase  (mixed case)                                                 │
│     ALL_CAPS   (underscores in middle)                                      │
│                                                                              │
│   INVALID identifiers:                                                      │
│     123abc     (starts with digit → it's a number!)                        │
│     foo-bar    (hyphen not allowed)                                         │
│     hello!     (punctuation not allowed)                                    │
│                                                                              │
│   Rule: Start with [a-zA-Z_], continue with [a-zA-Z0-9_]                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Helper Functions

```
function isAlpha(char):
    return (char >= 'a' AND char <= 'z')
        OR (char >= 'A' AND char <= 'Z')
        OR (char == '_')

function isAlphaNumeric(char):
    return isAlpha(char) OR isDigit(char)
```

---

## The Algorithm

```
function scanIdentifier():
    start = pos

    // First character is already checked (isAlpha)
    while isAlphaNumeric(peek()):
        advance()

    lexeme = source[start..pos]

    return Token {
        type: IDENTIFIER,
        lexeme: lexeme,
        line: line,
        column: start_column,
    }
```

---

## Updated nextToken()

```
function nextToken():
    skipWhitespace()

    if pos >= length(source):
        return Token(EOF)

    char = peek()

    if isDigit(char):
        return scanNumber()

    if char == '"':
        return scanString()

    if isAlpha(char):                    // ← ADD THIS
        return scanIdentifier()          // ← ADD THIS

    switch char:
        // ...
```

**Order matters!** Check `isDigit` before `isAlpha` because digits come first in the switch logic. But since digits can't start identifiers, either order works here.

---

## Verify Your Implementation

### Test 1: Simple identifier
```
Input:  "foo"
Tokens: [IDENTIFIER("foo")]
```

### Test 2: With digits
```
Input:  "bar123"
Tokens: [IDENTIFIER("bar123")]
```

### Test 3: Underscore
```
Input:  "_temp"
Tokens: [IDENTIFIER("_temp")]
```

### Test 4: Multiple identifiers
```
Input:  "foo bar baz"
Tokens: [IDENTIFIER("foo"), IDENTIFIER("bar"), IDENTIFIER("baz")]
```

### Test 5: In expression
```
Input:  "a + b"
Tokens: [IDENTIFIER("a"), PLUS, IDENTIFIER("b")]
```

### Test 6: Mixed with numbers
```
Input:  "x1 + 42"
Tokens: [IDENTIFIER("x1"), PLUS, NUMBER("42")]
```

---

## But Wait!

Right now, `fn` produces `IDENTIFIER("fn")`. But `fn` should be a keyword!

That's the next lesson.

---

## What's Next

Let's distinguish keywords like `fn`, `const`, `return` from regular identifiers.

Next: [Lesson 1.7: Keywords](../07-keywords/) →
