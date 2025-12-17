---
title: "1.8: Complete Lexer"
weight: 8
---

# Lesson 1.8: Putting It All Together

Let's assemble all the pieces into a complete, working lexer.

---

## Goal

Create a `tokenize(source)` function that returns all tokens from source code.

---

## Complete Lexer Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         COMPLETE LEXER                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Lexer {                                                                    │
│       source: string                                                         │
│       pos: integer                                                           │
│       line: integer                                                          │
│       column: integer                                                        │
│                                                                              │
│       // Helper functions                                                    │
│       peek() → char                                                          │
│       advance() → char                                                       │
│       isAtEnd() → bool                                                       │
│                                                                              │
│       // Whitespace                                                          │
│       skipWhitespace()                                                       │
│                                                                              │
│       // Token scanners                                                      │
│       scanNumber() → Token                                                   │
│       scanString() → Token                                                   │
│       scanIdentifier() → Token                                               │
│                                                                              │
│       // Main entry point                                                    │
│       nextToken() → Token                                                    │
│   }                                                                          │
│                                                                              │
│   function tokenize(source) → Token[]:                                      │
│       lexer = Lexer.init(source)                                            │
│       tokens = []                                                            │
│       while true:                                                            │
│           token = lexer.nextToken()                                          │
│           tokens.append(token)                                               │
│           if token.type == EOF:                                              │
│               break                                                          │
│       return tokens                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete nextToken()

```
function nextToken():
    skipWhitespace()

    if isAtEnd():
        return makeToken(EOF, 0)

    start_column = column
    char = peek()

    // Multi-character tokens
    if isDigit(char):
        return scanNumber()

    if char == '"':
        return scanString()

    if isAlpha(char):
        return scanIdentifier()

    // Single-character tokens
    switch char:
        '+' → return makeToken(PLUS, 1)
        '-' → return makeToken(MINUS, 1)
        '*' → return makeToken(STAR, 1)
        '/' → return makeToken(SLASH, 1)
        '=' → return makeToken(EQUAL, 1)
        '(' → return makeToken(LPAREN, 1)
        ')' → return makeToken(RPAREN, 1)
        '{' → return makeToken(LBRACE, 1)
        '}' → return makeToken(RBRACE, 1)
        ',' → return makeToken(COMMA, 1)
        ':' → return makeToken(COLON, 1)
        ';' → return makeToken(SEMICOLON, 1)
        else → return makeToken(INVALID, 1)
```

---

## Full Test Suite

### Test 1: Empty input
```
Input:  ""
Tokens: [EOF]
```

### Test 2: Just whitespace
```
Input:  "   \t\n  "
Tokens: [EOF]
```

### Test 3: Single token of each type
```
Input:  "42"
Tokens: [NUMBER("42"), EOF]

Input:  "foo"
Tokens: [IDENTIFIER("foo"), EOF]

Input:  "fn"
Tokens: [KEYWORD_FN, EOF]

Input:  "+"
Tokens: [PLUS, EOF]
```

### Test 4: Simple expression
```
Input:  "1 + 2"
Tokens: [NUMBER("1"), PLUS, NUMBER("2"), EOF]
```

### Test 5: Variable declaration
```
Input:  "const x = 42;"
Tokens: [KEYWORD_CONST, IDENTIFIER("x"), EQUAL, NUMBER("42"), SEMICOLON, EOF]
```

### Test 6: Function signature
```
Input:  "fn add(a: i32, b: i32) i32"
Tokens: [KEYWORD_FN, IDENTIFIER("add"), LPAREN, IDENTIFIER("a"), COLON,
         TYPE_I32, COMMA, IDENTIFIER("b"), COLON, TYPE_I32, RPAREN,
         TYPE_I32, EOF]
```

### Test 7: Complete function
```
Input:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

Tokens: [KEYWORD_FN, IDENTIFIER("add"), LPAREN, IDENTIFIER("a"), COLON,
         TYPE_I32, COMMA, IDENTIFIER("b"), COLON, TYPE_I32, RPAREN,
         TYPE_I32, LBRACE, KEYWORD_RETURN, IDENTIFIER("a"), PLUS,
         IDENTIFIER("b"), SEMICOLON, RBRACE, EOF]
```

### Test 8: Line numbers
```
Input:  "a\nb\nc"
Tokens:
  IDENTIFIER("a") at line 1
  IDENTIFIER("b") at line 2
  IDENTIFIER("c") at line 3
  EOF at line 3
```

---

## Error Handling

For invalid characters, you have options:

**Option A: Return INVALID token and continue**
```
Input:  "a @ b"
Tokens: [IDENTIFIER("a"), INVALID("@"), IDENTIFIER("b"), EOF]
```

**Option B: Stop on first error**
```
Input:  "a @ b"
Result: Error at line 1, column 3: unexpected character '@'
```

For learning, Option A is easier. For production, you might want Option B or collect all errors.

---

## Congratulations!

You now have a working lexer that can tokenize our mini language:

```
fn main() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    return x + y;
}
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         LEXER SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. SETUP          Token and Lexer data structures                         │
│   2. SINGLE CHARS   Operators and delimiters                                │
│   3. WHITESPACE     Skip spaces, track line numbers                         │
│   4. NUMBERS        Digit sequences                                          │
│   5. STRINGS        Quoted text                                              │
│   6. IDENTIFIERS    Names (letters, digits, underscores)                    │
│   7. KEYWORDS       Reserved words (fn, const, return, i32)                 │
│   8. INTEGRATION    Put it all together                                      │
│                                                                              │
│   Lines of code: ~100-150 depending on language                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

With tokens in hand, we can build the parser to create an Abstract Syntax Tree.

Next: [Section 2: The Parser](../../02-parser/) →
