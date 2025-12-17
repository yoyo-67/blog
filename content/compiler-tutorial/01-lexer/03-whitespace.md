---
title: "1.3: Whitespace"
weight: 3
---

# Lesson 1.3: Handling Whitespace

Spaces, tabs, and newlines separate tokens but aren't tokens themselves. Let's skip them.

---

## Goal

Modify `nextToken()` to skip whitespace before returning a token.

---

## What is Whitespace?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            WHITESPACE CHARACTERS                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ' '   Space (ASCII 32)                                                    │
│   '\t'  Tab (ASCII 9)                                                       │
│   '\n'  Newline (ASCII 10)         ← Increment line counter!                │
│   '\r'  Carriage return (ASCII 13)                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Algorithm

```
function skipWhitespace():
    while true:
        char = peek()
        switch char:
            ' ', '\t', '\r':
                advance()
            '\n':
                advance()
                line = line + 1
                column = 1
            else:
                return  // Not whitespace, stop
```

---

## Updated nextToken()

```
function nextToken():
    skipWhitespace()          // ← ADD THIS LINE

    if pos >= length(source):
        return Token(EOF)

    // ... rest of the switch statement
```

---

## Tracking Line Numbers

When we see a newline, we must update our position:

```
'\n':
    advance()
    line = line + 1      // Move to next line
    column = 1           // Reset to column 1
```

This is crucial for error messages like:
```
Error at line 5, column 12: unexpected token
```

---

## Verify Your Implementation

### Test 1: Spaces between operators
```
Input:  "+ - *"
Tokens: [PLUS, MINUS, STAR]
```

### Test 2: Tabs
```
Input:  "+\t-"
Tokens: [PLUS, MINUS]
```

### Test 3: Newlines
```
Input:  "+\n-"
Tokens: [PLUS, MINUS]
Check:  Second token should have line=2
```

### Test 4: Multiple newlines
```
Input:  "+\n\n\n-"
Tokens: [PLUS, MINUS]
Check:  Second token should have line=4
```

### Test 5: Mixed whitespace
```
Input:  "  +  \t\n  -  "
Tokens: [PLUS, MINUS]
```

### Test 6: Only whitespace
```
Input:  "   \t\n   "
Tokens: [EOF]
```

---

## What's Next

Now we can handle spaces! But `42` still produces `[INVALID, INVALID]`. Let's fix numbers.

Next: [Lesson 1.4: Numbers](../04-numbers/) →
