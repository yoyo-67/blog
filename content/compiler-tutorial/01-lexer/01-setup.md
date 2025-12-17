---
title: "1.1: Token Setup"
weight: 1
---

# Lesson 1.1: Token Setup

Before we can tokenize anything, we need to define what a **token** is.

---

## Goal

Define the data structures for tokens that will be used throughout the lexer.

---

## What is a Token?

A token is a small piece of source code with a **type** and a **value**:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                             TOKEN STRUCTURE                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Token {                                                                    │
│       type:   What kind of token (keyword? number? operator?)               │
│       lexeme: The actual text from the source ("const", "42", "+")          │
│       line:   Which line it's on (for error messages)                       │
│       column: Which column it starts at (for error messages)                │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Token Types

Define an enumeration of all possible token types. For our mini language:

```
TokenType = enum {
    // Keywords
    KEYWORD_FN,
    KEYWORD_CONST,
    KEYWORD_VAR,
    KEYWORD_RETURN,
    KEYWORD_TRUE,
    KEYWORD_FALSE,

    // Types
    TYPE_I32,
    TYPE_I64,
    TYPE_BOOL,
    TYPE_VOID,

    // Literals
    NUMBER,        // 42, 0, 123
    STRING,        // "hello"
    IDENTIFIER,    // foo, bar, x

    // Operators
    PLUS,          // +
    MINUS,         // -
    STAR,          // *
    SLASH,         // /
    EQUAL,         // =

    // Delimiters
    LPAREN,        // (
    RPAREN,        // )
    LBRACE,        // {
    RBRACE,        // }
    COMMA,         // ,
    COLON,         // :
    SEMICOLON,     // ;

    // Special
    EOF,           // End of file
    INVALID,       // Unrecognized character
}
```

---

## Token Structure

```
Token = struct {
    type:   TokenType,
    lexeme: string,      // The actual text
    line:   integer,     // 1-indexed line number
    column: integer,     // 1-indexed column number
}
```

**Note on lexeme storage**: For efficiency, instead of copying strings, you can store start/end indices into the source:

```
Token = struct {
    type:   TokenType,
    start:  integer,     // Start index in source
    end:    integer,     // End index in source
    line:   integer,
    column: integer,
}

// To get the text:
lexeme = source[token.start .. token.end]
```

This avoids memory allocation for each token.

---

## Lexer Structure

The lexer holds state as it scans through the source:

```
Lexer = struct {
    source: string,      // The entire source code
    pos:    integer,     // Current position in source
    line:   integer,     // Current line number
    column: integer,     // Current column number
}
```

---

## Implementation Steps

1. **Define TokenType enum** with all token types listed above
2. **Define Token struct** with type, lexeme (or start/end), line, column
3. **Define Lexer struct** with source, pos, line, column
4. **Create Lexer.init(source)** that initializes a new lexer

---

## Verify Your Implementation

### Test 1: Create a lexer
```
Input:  Lexer.init("hello world")
Check:  lexer.source == "hello world"
        lexer.pos == 0
        lexer.line == 1
        lexer.column == 1
```

### Test 2: Token creation
```
Create: Token { type: PLUS, lexeme: "+", line: 1, column: 5 }
Check:  token.type == PLUS
        token.lexeme == "+"
```

---

## What's Next

Now that we have the data structures, let's implement the first tokenizing logic.

Next: [Lesson 1.2: Single Character Tokens](../02-single-chars/) →
