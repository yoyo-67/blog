---
title: "1.4: Numbers"
weight: 4
---

# Lesson 1.4: Integer Literals

Let's recognize numbers like `42`, `0`, and `12345`.

---

## Goal

Recognize sequences of digits as NUMBER tokens.

---

## The Key Insight

A number starts with a digit and continues while we see more digits:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           NUMBER RECOGNITION                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   "123 + 456"                                                               │
│    ^^^                                                                       │
│    │└┴── Keep going while we see digits                                     │
│    └──── Starts with a digit → it's a number!                               │
│                                                                              │
│   function isDigit(char):                                                   │
│       return char >= '0' AND char <= '9'                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Algorithm

```
function scanNumber():
    start = pos

    // Consume all consecutive digits
    while isDigit(peek()):
        advance()

    return Token {
        type: NUMBER,
        lexeme: source[start..pos],
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

    // Check for number FIRST
    if isDigit(char):                    // ← ADD THIS
        return scanNumber()              // ← ADD THIS

    // Then check single characters
    switch char:
        '+' → ...
        // etc.
```

---

## Helper Function

```
function isDigit(char):
    return char >= '0' AND char <= '9'
```

Or using ASCII values:
```
function isDigit(char):
    return char >= 48 AND char <= 57  // '0'=48, '9'=57
```

---

## Verify Your Implementation

### Test 1: Single digit
```
Input:  "5"
Tokens: [NUMBER("5")]
```

### Test 2: Multi-digit
```
Input:  "123"
Tokens: [NUMBER("123")]
```

### Test 3: Zero
```
Input:  "0"
Tokens: [NUMBER("0")]
```

### Test 4: Number in expression
```
Input:  "3 + 42"
Tokens: [NUMBER("3"), PLUS, NUMBER("42")]
```

### Test 5: Adjacent numbers
```
Input:  "12 34 56"
Tokens: [NUMBER("12"), NUMBER("34"), NUMBER("56")]
```

### Test 6: Number followed by operator
```
Input:  "42+"
Tokens: [NUMBER("42"), PLUS]
```

---

## What You're NOT Handling (Yet)

For simplicity, we skip these:
- Floating point: `3.14`
- Negative numbers: `-42` (handle as MINUS followed by NUMBER)
- Hex/binary: `0xFF`, `0b1010`
- Underscores: `1_000_000`

These can be added later as extensions.

---

## What's Next

We can now handle numbers! But what about string literals like `"hello"`?

Next: [Lesson 1.5: Strings](../05-strings/) →
