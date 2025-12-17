---
title: "1.5: Strings"
weight: 5
---

# Lesson 1.5: String Literals (Optional)

String literals like `"hello world"` are enclosed in quotes.

---

## Goal

Recognize text between double quotes as STRING tokens.

---

## The Pattern

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           STRING RECOGNITION                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   "hello world"                                                              │
│   ^            ^                                                             │
│   │            └── Ending quote                                             │
│   └── Starting quote                                                         │
│                                                                              │
│   Everything between quotes is the string content.                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Algorithm

```
function scanString():
    advance()  // consume opening "
    start = pos

    while peek() != '"' AND peek() != '\0':
        if peek() == '\n':
            line = line + 1
            column = 1
        advance()

    if peek() == '\0':
        return Token(INVALID)  // Unterminated string

    content = source[start..pos]
    advance()  // consume closing "

    return Token {
        type: STRING,
        lexeme: content,
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

    if char == '"':                      // ← ADD THIS
        return scanString()              // ← ADD THIS

    switch char:
        // ...
```

---

## Verify Your Implementation

### Test 1: Simple string
```
Input:  "hello"
        (including the quotes)
Tokens: [STRING("hello")]
```

### Test 2: String with spaces
```
Input:  "hello world"
Tokens: [STRING("hello world")]
```

### Test 3: Empty string
```
Input:  ""
Tokens: [STRING("")]
```

### Test 4: String in expression
```
Input:  x = "value"
Tokens: [IDENTIFIER, EQUAL, STRING("value")]
```

### Test 5: Unterminated string
```
Input:  "hello
Tokens: [INVALID]
```

---

## Escape Sequences (Optional Extension)

For a more complete implementation, handle escape sequences:

```
\"  → literal quote
\\  → literal backslash
\n  → newline
\t  → tab
```

This requires more complex parsing but isn't needed for our mini compiler.

---

## Note: Strings Are Optional

Our mini compiler focuses on arithmetic and functions. Strings are nice to have but not essential. If you skip this lesson, the compiler will still work for numeric programs.

---

## What's Next

Now let's handle variable names like `foo` and `bar123`.

Next: [Lesson 1.6: Identifiers](../06-identifiers/) →
