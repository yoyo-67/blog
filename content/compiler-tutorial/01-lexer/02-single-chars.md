---
title: "1.2: Single Character Tokens"
weight: 2
---

# Lesson 1.2: Single Character Tokens

Let's tokenize the simplest case: single-character tokens like `+`, `-`, `(`, `)`.

---

## Goal

Implement a `nextToken()` function that recognizes single-character operators and delimiters.

---

## The Algorithm

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SINGLE CHARACTER LEXING                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   function nextToken():                                                      │
│       if pos >= length(source):                                              │
│           return Token(EOF)                                                  │
│                                                                              │
│       char = source[pos]                                                     │
│                                                                              │
│       switch char:                                                           │
│           '+' → advance(), return Token(PLUS)                               │
│           '-' → advance(), return Token(MINUS)                              │
│           '*' → advance(), return Token(STAR)                               │
│           '/' → advance(), return Token(SLASH)                              │
│           '=' → advance(), return Token(EQUAL)                              │
│           '(' → advance(), return Token(LPAREN)                             │
│           ')' → advance(), return Token(RPAREN)                             │
│           '{' → advance(), return Token(LBRACE)                             │
│           '}' → advance(), return Token(RBRACE)                             │
│           ',' → advance(), return Token(COMMA)                              │
│           ':' → advance(), return Token(COLON)                              │
│           ';' → advance(), return Token(SEMICOLON)                          │
│           else → advance(), return Token(INVALID)                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Helper Functions

You'll need these helper functions:

### peek()
Look at current character without consuming it:
```
function peek():
    if pos >= length(source):
        return '\0'  // or null
    return source[pos]
```

### advance()
Consume current character and move forward:
```
function advance():
    if pos >= length(source):
        return '\0'
    char = source[pos]
    pos = pos + 1
    column = column + 1
    return char
```

### makeToken(type, length)
Create a token from current position:
```
function makeToken(type, length):
    start = pos
    for i in 0..length:
        advance()
    return Token {
        type: type,
        lexeme: source[start..pos],
        line: line,
        column: start_column,
    }
```

---

## Implementation Steps

1. **Implement peek()** - return current char without advancing
2. **Implement advance()** - return current char AND advance position
3. **Implement makeToken()** - create token from current position
4. **Implement nextToken()** - switch on current character

---

## Verify Your Implementation

### Test 1: Single operator
```
Input:  "+"
Tokens: [PLUS]
```

### Test 2: Multiple operators
```
Input:  "+-*/"
Tokens: [PLUS, MINUS, STAR, SLASH]
```

### Test 3: Delimiters
```
Input:  "()"
Tokens: [LPAREN, RPAREN]
```

### Test 4: Mixed
```
Input:  "(){}:;"
Tokens: [LPAREN, RPAREN, LBRACE, RBRACE, COLON, SEMICOLON]
```

### Test 5: Unknown character
```
Input:  "@"
Tokens: [INVALID]
```

### Test 6: Empty input
```
Input:  ""
Tokens: [EOF]
```

---

## Edge Cases to Handle

1. **Empty source** → Return EOF immediately
2. **Unknown character** → Return INVALID token
3. **End of file** → Return EOF token

---

## What's Next

Our lexer works but treats spaces as invalid! Let's fix that.

Next: [Lesson 1.3: Whitespace](../03-whitespace/) →
