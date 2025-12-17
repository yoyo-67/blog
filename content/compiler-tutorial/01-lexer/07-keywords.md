---
title: "1.7: Keywords"
weight: 7
---

# Lesson 1.7: Keywords

Keywords are reserved words with special meaning: `fn`, `const`, `return`, `i32`.

---

## Goal

After scanning an identifier, check if it's actually a keyword.

---

## The Approach

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          KEYWORD RECOGNITION                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Instead of:                                                                │
│     "fn" → IDENTIFIER("fn")     ✗ Wrong!                                    │
│                                                                              │
│   We want:                                                                   │
│     "fn" → KEYWORD_FN           ✓ Correct!                                  │
│                                                                              │
│   Strategy:                                                                  │
│   1. Scan the identifier as usual                                           │
│   2. Look up the lexeme in a keyword table                                  │
│   3. If found, return keyword token; else return identifier                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Keyword Table

Create a lookup table mapping strings to token types:

```
KEYWORDS = {
    "fn":     KEYWORD_FN,
    "pub":    KEYWORD_PUB,
    "const":  KEYWORD_CONST,
    "var":    KEYWORD_VAR,
    "return": KEYWORD_RETURN,
    "true":   KEYWORD_TRUE,
    "false":  KEYWORD_FALSE,

    // Type keywords
    "i32":    TYPE_I32,
    "i64":    TYPE_I64,
    "bool":   TYPE_BOOL,
    "void":   TYPE_VOID,
}
```

---

## Updated scanIdentifier()

```
function scanIdentifier():
    start = pos

    while isAlphaNumeric(peek()):
        advance()

    lexeme = source[start..pos]

    // Look up in keyword table
    type = KEYWORDS.get(lexeme)          // ← ADD THIS
    if type == null:                     // ← ADD THIS
        type = IDENTIFIER                // ← ADD THIS

    return Token {
        type: type,                      // Could be keyword or identifier
        lexeme: lexeme,
        line: line,
        column: start_column,
    }
```

---

## Implementation Options

### Option A: Hash Map
```
keywords = HashMap()
keywords.put("fn", KEYWORD_FN)
keywords.put("const", KEYWORD_CONST)
// etc.

function lookupIdentifier(lexeme):
    return keywords.get(lexeme) ?? IDENTIFIER
```

### Option B: If-Else Chain (Simple)
```
function lookupIdentifier(lexeme):
    if lexeme == "fn": return KEYWORD_FN
    if lexeme == "const": return KEYWORD_CONST
    if lexeme == "var": return KEYWORD_VAR
    if lexeme == "return": return KEYWORD_RETURN
    if lexeme == "i32": return TYPE_I32
    // etc.
    return IDENTIFIER
```

### Option C: Switch Statement
```
function lookupIdentifier(lexeme):
    switch lexeme:
        "fn"     → return KEYWORD_FN
        "const"  → return KEYWORD_CONST
        "return" → return KEYWORD_RETURN
        // etc.
        default  → return IDENTIFIER
```

For a small number of keywords, any approach works. Hash maps are better for large keyword sets.

---

## Verify Your Implementation

### Test 1: Keywords
```
Input:  "fn"
Tokens: [KEYWORD_FN]

Input:  "const"
Tokens: [KEYWORD_CONST]

Input:  "return"
Tokens: [KEYWORD_RETURN]
```

### Test 2: Type keywords
```
Input:  "i32"
Tokens: [TYPE_I32]

Input:  "bool"
Tokens: [TYPE_BOOL]
```

### Test 3: Not keywords (identifiers)
```
Input:  "foo"
Tokens: [IDENTIFIER("foo")]

Input:  "fn123"
Tokens: [IDENTIFIER("fn123")]  // Not "fn" + "123"!

Input:  "constValue"
Tokens: [IDENTIFIER("constValue")]  // Not KEYWORD_CONST!
```

### Test 4: Mixed
```
Input:  "fn add"
Tokens: [KEYWORD_FN, IDENTIFIER("add")]
```

### Test 5: Function declaration
```
Input:  "fn main() i32"
Tokens: [KEYWORD_FN, IDENTIFIER("main"), LPAREN, RPAREN, TYPE_I32]
```

---

## Case Sensitivity

Our language is case-sensitive:
- `fn` → KEYWORD_FN
- `FN` → IDENTIFIER("FN")
- `Fn` → IDENTIFIER("Fn")

This matches languages like C, Go, Zig, and Rust.

---

## What's Next

We have all the pieces! Let's put them together into a complete lexer.

Next: [Lesson 1.8: Complete Lexer](../08-putting-together/) →
