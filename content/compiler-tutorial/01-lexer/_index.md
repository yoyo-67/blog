---
title: "Section 1: The Lexer"
weight: 1
---

# Section 1: The Lexer

The lexer (also called tokenizer or scanner) is the first stage of our compiler. It transforms raw source text into a stream of **tokens** - the smallest meaningful units of our language.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           WHAT THE LEXER DOES                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input:  "const x = 42 + y;"                                               │
│                                                                              │
│   Output: [CONST] [IDENT:"x"] [EQUAL] [NUMBER:42] [PLUS] [IDENT:"y"] [SEMI] │
│                                                                              │
│   The lexer:                                                                 │
│   ✓ Breaks text into chunks (tokens)                                        │
│   ✓ Classifies each chunk (keyword? number? operator?)                      │
│   ✓ Discards whitespace and comments                                        │
│   ✗ Does NOT check if the code makes sense                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Do We Need a Lexer?

Imagine trying to parse raw text character by character. For `const x = 42`:

```
Without lexer:
  'c' → is this the start of "const"? or "continue"? or variable "count"?
  'o' → still not sure...
  'n' → maybe "const"?
  's' → probably "const"!
  't' → yes, "const"!
  ' ' → ok, that word is done
  'x' → new identifier starting...
  ... exhausting!

With lexer:
  Token 1: KEYWORD_CONST
  Token 2: IDENTIFIER("x")
  Token 3: EQUAL
  Token 4: NUMBER(42)
  Much easier!
```

The lexer handles the messy character-by-character work so the parser can think in terms of whole tokens.

---

## Lessons in This Section

| Lesson | Topic | What You'll Add |
|--------|-------|-----------------|
| [1. Setup](01-setup/) | Token structure | Define what a token looks like |
| [2. Single Characters](02-single-chars/) | Operators & delimiters | `+`, `-`, `*`, `/`, `(`, `)`, etc. |
| [3. Whitespace](03-whitespace/) | Skip blanks | Spaces, tabs, newlines |
| [4. Numbers](04-numbers/) | Integer literals | `42`, `0`, `12345` |
| [5. Strings](05-strings/) | String literals | `"hello world"` |
| [6. Identifiers](06-identifiers/) | Variable names | `foo`, `bar123`, `_temp` |
| [7. Keywords](07-keywords/) | Reserved words | `fn`, `const`, `return` |
| [8. Complete Lexer](08-putting-together/) | Integration | Full lexer with tests |

---

## What You'll Build

By the end of this section, you'll have a working lexer that can handle:

```
fn add(a: i32, b: i32) i32 {
    const result: i32 = a + b;
    return result;
}
```

And produce:
```
[FN] [IDENT:"add"] [LPAREN] [IDENT:"a"] [COLON] [TYPE_I32] [COMMA]
[IDENT:"b"] [COLON] [TYPE_I32] [RPAREN] [TYPE_I32] [LBRACE]
[CONST] [IDENT:"result"] [COLON] [TYPE_I32] [EQUAL] [IDENT:"a"]
[PLUS] [IDENT:"b"] [SEMICOLON] [RETURN] [IDENT:"result"] [SEMICOLON]
[RBRACE] [EOF]
```

---

## Start Here

Begin with [Lesson 1: Token Setup](01-setup/) →
