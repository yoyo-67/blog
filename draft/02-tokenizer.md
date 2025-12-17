---
title: "Zig Compiler Internals Part 2: The Tokenizer"
date: 2025-12-17
---

# Zig Compiler Internals Part 2: The Tokenizer

*Converting source code into tokens with a hand-crafted state machine*

---

## Introduction

Before the Zig compiler can understand your code, it must first break it down into its smallest meaningful pieces: **tokens**. This process, called **lexical analysis** or **tokenization**, is the first step in the compilation pipeline.

In this article, we'll explore Zig's tokenizer, a beautifully hand-crafted state machine that efficiently converts source text into a stream of tokens.

## The Big Picture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SOURCE CODE                                      │
│                                                                          │
│    const x: u32 = 42;                                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         TOKENIZER                                        │
│                                                                          │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐              │
│   │  State  │───▶│  Read   │───▶│ Decide  │───▶│  Emit   │              │
│   │ Machine │    │  Char   │    │  Next   │    │  Token  │              │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         TOKEN STREAM                                     │
│                                                                          │
│   [const] [x] [:] [u32] [=] [42] [;] [EOF]                               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## The Tokenizer at a Glance

**Location**: `lib/std/zig/tokenizer.zig` (1,769 lines)

Key statistics:
- **185 token types** (keywords, operators, literals, etc.)
- **41 states** in the state machine
- **59 keywords** recognized
- Hand-written, no parser generators

## Token Structure

Every token in Zig has a simple structure:

```zig
pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,  // Byte offset in source
        end: usize,    // Byte offset in source
    };
};
```

Tokens don't store the actual text - they just reference positions in the original source:

```
Source: "const x: u32 = 42;"
         ▲     ▲
         │     │
         │     └── end = 5
         └── start = 0

Token { .tag = .keyword_const, .loc = { .start = 0, .end = 5 } }

To get the text: source[0..5] = "const"
```

This is memory-efficient and enables zero-copy parsing.

## Understanding the State Machine

The tokenizer works like a vending machine - it reads characters one by one and transitions between states until it has a complete token.

### State Machine Overview

```
                              ┌─────────────────────────────────────────┐
                              │              START STATE                 │
                              │                                          │
                              │   Read first character, decide where     │
                              │   to go based on what we see             │
                              └─────────────────────────────────────────┘
                                                 │
               ┌─────────────────┬───────────────┼───────────────┬─────────────────┐
               │                 │               │               │                 │
               ▼                 ▼               ▼               ▼                 ▼
        ┌─────────────┐   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   ┌─────────────┐
        │ a-z, A-Z, _ │   │    0-9      │ │   " or '    │ │  + - * / =  │   │   @ sign    │
        │             │   │             │ │             │ │   etc...    │   │             │
        │ IDENTIFIER  │   │   NUMBER    │ │   STRING    │ │  OPERATOR   │   │  BUILTIN    │
        └─────────────┘   └─────────────┘ └─────────────┘ └─────────────┘   └─────────────┘
               │                 │               │               │                 │
               ▼                 ▼               ▼               ▼                 ▼
        ┌─────────────────────────────────────────────────────────────────────────────────┐
        │                              EMIT TOKEN                                          │
        │                                                                                  │
        │   Return to START state, ready for next token                                    │
        └─────────────────────────────────────────────────────────────────────────────────┘
```

### The 41 States

```zig
const State = enum {
    start,                              // Initial state
    expect_newline,                     // After certain tokens

    // Identifiers and keywords
    identifier,                         // Reading: foo, Bar, _name
    builtin,                            // Reading: @import, @as

    // Strings and characters
    string_literal,                     // Reading: "hello"
    string_literal_backslash,           // Reading: "hel\...
    multiline_string_literal_line,      // Reading: \\text
    char_literal,                       // Reading: 'x'
    char_literal_backslash,             // Reading: '\...
    backslash,                          // Saw: \

    // Multi-character operators
    equal,                              // Saw: =  (could be = or ==)
    bang,                               // Saw: !  (could be ! or !=)
    pipe,                               // Saw: |  (could be | or || or |=)
    minus,                              // Saw: -  (could be - or -= or -%)
    minus_percent,                      // Saw: -%
    minus_pipe,                         // Saw: -|
    asterisk,                           // Saw: *  (could be * or *= or *%)
    asterisk_percent,                   // Saw: *%
    asterisk_pipe,                      // Saw: *|
    slash,                              // Saw: /  (could be / or /= or //)
    plus,                               // Saw: +  (could be + or += or +%)
    plus_percent,                       // Saw: +%
    plus_pipe,                          // Saw: +|
    ampersand,                          // Saw: &
    caret,                              // Saw: ^
    percent,                            // Saw: %

    // Comments
    line_comment_start,                 // Saw: //
    line_comment,                       // Inside: // comment text
    doc_comment_start,                  // Saw: ///
    doc_comment,                        // Inside: /// doc text

    // Numbers
    int,                                // Reading: 123
    int_exponent,                       // Reading: 1e...
    int_period,                         // Reading: 1.
    float,                              // Reading: 1.23
    float_exponent,                     // Reading: 1.23e-4

    // Angle brackets (tricky!)
    angle_bracket_left,                 // Saw: <
    angle_bracket_angle_bracket_left,   // Saw: <<
    angle_bracket_angle_bracket_left_pipe, // Saw: <<|
    angle_bracket_right,                // Saw: >
    angle_bracket_angle_bracket_right,  // Saw: >>

    // Periods
    period,                             // Saw: .
    period_2,                           // Saw: ..
    period_asterisk,                    // Saw: .*

    // Special
    saw_at_sign,                        // Saw: @
    invalid,                            // Error recovery
};
```

## Step-by-Step Example: Tokenizing `const`

Let's trace through how `const x = 5;` gets tokenized:

```
Input: "const x = 5;"
        ^
        index = 0

Step 1: START state, see 'c' (letter)
        ─────────────────────────────

        ┌─────┐     'c'      ┌────────────┐
        │START│ ───────────▶ │ IDENTIFIER │
        └─────┘              └────────────┘

        Set tag = .identifier
        Continue reading...

Step 2: IDENTIFIER state, see 'o' (letter)
        ───────────────────────────────────

        "const x = 5;"
          ^
          index = 1

        ┌────────────┐  'o'  ┌────────────┐
        │ IDENTIFIER │ ────▶ │ IDENTIFIER │
        └────────────┘       └────────────┘

        Still in identifier, keep going...

Step 3-5: Keep reading 'n', 's', 't'
        ─────────────────────────────

        "const x = 5;"
              ^
              index = 5

        Still identifier characters, stay in state

Step 6: IDENTIFIER state, see ' ' (space)
        ──────────────────────────────────

        "const x = 5;"
               ^
               index = 5

        Space is NOT an identifier character!

        ┌────────────┐  ' '  ┌──────────────────┐
        │ IDENTIFIER │ ────▶ │ CHECK IF KEYWORD │
        └────────────┘       └──────────────────┘

        Extract text: source[0..5] = "const"
        Look up in keyword table: "const" → .keyword_const

        EMIT TOKEN: { .tag = .keyword_const, .loc = {0, 5} }
```

### Visual Token Extraction

```
Source String:
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ c │ o │ n │ s │ t │   │ x │   │ = │   │ 5 │ ; │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
  0   1   2   3   4   5   6   7   8   9  10  11

Token 1: "const"
├───────────────────┤
start=0           end=5

Token 2: "x"
                    ├───┤
                  start=6 end=7

Token 3: "="
                            ├───┤
                          start=8 end=9

Token 4: "5"
                                    ├────┤
                                  start=10 end=11

Token 5: ";"
                                         ├───┤
                                       start=11 end=12
```

## Identifier State Machine (Source Code Deep Dive)

Let's look at the **actual source code** from `lib/std/zig/tokenizer.zig` that handles identifiers and keywords:

### Entry Point: START State (Lines 431-434)

When the tokenizer sees a letter or underscore in the start state:

```zig
// In the START state switch:
'a'...'z', 'A'...'Z', '_' => {
    result.tag = .identifier;
    continue :state .identifier;
},
```

This immediately:
1. Sets the token tag to `.identifier` (may be changed to keyword later)
2. Transitions to the `identifier` state

### Identifier State Loop (Lines 664-675)

```zig
.identifier => {
    self.index += 1;
    switch (self.buffer[self.index]) {
        'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
        else => {
            const ident = self.buffer[result.loc.start..self.index];
            if (Token.getKeyword(ident)) |tag| {
                result.tag = tag;
            }
        },
    }
},
```

Key observations:
- **Valid identifier characters**: `a-z`, `A-Z`, `_`, `0-9` (but can't start with digit)
- **Termination**: Any other character ends the identifier
- **Keyword lookup**: After termination, checks if it's a keyword

### Keyword Lookup: Compile-Time Perfect Hash (Lines 12-63)

```zig
pub fn getKeyword(bytes: []const u8) ?Tag {
    return keywords.get(bytes);
}

const keywords = std.StaticStringMap(Tag).initComptime(.{
    .{ "addrspace", .keyword_addrspace },
    .{ "align", .keyword_align },
    .{ "allowzero", .keyword_allowzero },
    .{ "and", .keyword_and },
    .{ "anyframe", .keyword_anyframe },
    .{ "anytype", .keyword_anytype },
    .{ "asm", .keyword_asm },
    .{ "async", .keyword_async },
    .{ "await", .keyword_await },
    .{ "break", .keyword_break },
    .{ "callconv", .keyword_callconv },
    .{ "catch", .keyword_catch },
    .{ "comptime", .keyword_comptime },
    .{ "const", .keyword_const },
    // ... 45 more keywords ...
    .{ "while", .keyword_while },
});
```

The `StaticStringMap` creates a **compile-time perfect hash table** for O(1) keyword lookups!

### Visual State Machine

```
                ┌─────────────────────────────────────────────────────────────┐
                │                    START STATE                               │
                │                                                              │
                │   See 'a'-'z', 'A'-'Z', '_'                                 │
                └─────────────────────────────────────────────────────────────┘
                                        │
                                        │ Set tag = .identifier
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           IDENTIFIER STATE                                       │
│                                                                                  │
│   ┌──────────────────────────────────────────────────────────────────────────┐  │
│   │                         LOOP HERE                                         │  │
│   │                                                                           │  │
│   │   See 'a'-'z', 'A'-'Z', '_', '0'-'9'  ───▶  Stay in IDENTIFIER state     │  │
│   │                          │                                                │  │
│   │                          └─────────────────────────────────────────────┐  │  │
│   │                                                                        │  │  │
│   │   ┌────────────────────────────────────────────────────────────────────┘  │  │
│   │   │                                                                       │  │
│   │   ▼                                                                       │  │
│   │   ┌───┐  'a'-'z'    ┌───┐  'A'-'Z'    ┌───┐  '_'    ┌───┐  '0'-'9'       │  │
│   │   │ c │ ─────────▶  │ o │ ─────────▶  │ n │ ─────▶  │ s │ ─────────▶ ... │  │
│   │   └───┘             └───┘             └───┘         └───┘                 │  │
│   │                                                                           │  │
│   └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        │ See anything else (space, operator, etc.)
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           TERMINATION                                            │
│                                                                                  │
│   1. Extract text: buffer[start..index]                                         │
│                                                                                  │
│   2. Check keyword table:                                                        │
│      ┌──────────────────────────────────────────────────────────────────────┐   │
│      │                    StaticStringMap Lookup                             │   │
│      │                                                                       │   │
│      │   "const"  ──▶  .keyword_const     ✓                                 │   │
│      │   "if"     ──▶  .keyword_if        ✓                                 │   │
│      │   "foo"    ──▶  null (not keyword) ✗                                 │   │
│      │   "myVar"  ──▶  null (not keyword) ✗                                 │   │
│      └──────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   3. If keyword found: result.tag = keyword_tag                                 │
│      Else: result.tag stays .identifier                                         │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
                              EMIT TOKEN & RETURN
```

### Example Trace: Tokenizing `const`

```
Input: "const x = 5"
        ^
        index = 0

┌──────────────────────────────────────────────────────────────────────────────────┐
│ Step │ Index │ Char │ State      │ Action                         │ tag          │
├──────────────────────────────────────────────────────────────────────────────────┤
│  1   │   0   │ 'c'  │ start      │ See letter, set tag            │ .identifier  │
│      │       │      │            │ → identifier state             │              │
├──────────────────────────────────────────────────────────────────────────────────┤
│  2   │   1   │ 'o'  │ identifier │ index++, see letter            │ .identifier  │
│      │       │      │            │ continue :state .identifier    │              │
├──────────────────────────────────────────────────────────────────────────────────┤
│  3   │   2   │ 'n'  │ identifier │ index++, see letter            │ .identifier  │
│      │       │      │            │ continue :state .identifier    │              │
├──────────────────────────────────────────────────────────────────────────────────┤
│  4   │   3   │ 's'  │ identifier │ index++, see letter            │ .identifier  │
│      │       │      │            │ continue :state .identifier    │              │
├──────────────────────────────────────────────────────────────────────────────────┤
│  5   │   4   │ 't'  │ identifier │ index++, see letter            │ .identifier  │
│      │       │      │            │ continue :state .identifier    │              │
├──────────────────────────────────────────────────────────────────────────────────┤
│  6   │   5   │ ' '  │ identifier │ index++, see SPACE             │              │
│      │       │      │            │ NOT identifier char!           │              │
│      │       │      │            │                                │              │
│      │       │      │            │ Extract: buffer[0..5]="const"  │              │
│      │       │      │            │                                │              │
│      │       │      │            │ Lookup: getKeyword("const")    │              │
│      │       │      │            │ Result: .keyword_const         │              │
│      │       │      │            │                                │              │
│      │       │      │            │ Set tag = .keyword_const       │.keyword_const│
├──────────────────────────────────────────────────────────────────────────────────┤
│      │       │      │            │ EMIT TOKEN                     │              │
│      │       │      │            │ { .tag = .keyword_const,       │              │
│      │       │      │            │   .loc = { 0, 5 } }            │              │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Valid vs Invalid Identifiers

```
Valid Identifiers:
┌─────────────────┬────────────────────────────────────────────────────────────┐
│ foo             │ Simple lowercase                                           │
│ Bar             │ Capitalized (often types)                                  │
│ _private        │ Underscore prefix (convention: private/internal)           │
│ camelCase       │ Mixed case                                                 │
│ snake_case      │ Underscores                                                │
│ Point2D         │ Alphanumeric after first char                             │
│ __builtin       │ Double underscore (compiler internals)                     │
│ a               │ Single character                                           │
│ _               │ Single underscore                                          │
│ @"while"        │ Escaped keyword (quoted identifier) - special syntax       │
└─────────────────┴────────────────────────────────────────────────────────────┘

Invalid Identifiers (won't parse as identifier):
┌─────────────────┬────────────────────────────────────────────────────────────┐
│ 2fast           │ Can't start with digit → parsed as number then identifier │
│ my-var          │ Hyphen not allowed → parsed as my, minus, var             │
│ hello world     │ Space breaks it → two identifiers                         │
│ const           │ Keyword → .keyword_const (not .identifier)                │
└─────────────────┴────────────────────────────────────────────────────────────┘
```

### Escaped Identifiers: `@"..."` Syntax

Zig has a special escape hatch for using reserved words as identifiers:

```zig
// This is a compile error:
var while = 5;  // "while" is a keyword!

// This works - escaped identifier:
var @"while" = 5;  // @"while" is the identifier
```

This is handled by a separate state machine branch for `@"..."` syntax.

## Operator State Machines

Operators are tricky because they can have multiple characters. Here's how `+` is handled:

### The Plus Operator Family

```
                    ┌─────────────────────────────────────────┐
                    │              SAW '+'                     │
                    │                                          │
                    │   Could be:  +  +=  +%  +%=  +|  +|=     │
                    └─────────────────────────────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    │                   │                   │
                    ▼                   ▼                   ▼
             ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
             │  See '='    │     │  See '%'    │     │  See '|'    │
             │             │     │             │     │             │
             │  Emit +=    │     │  PLUS_PERC  │     │  PLUS_PIPE  │
             └─────────────┘     └─────────────┘     └─────────────┘
                                        │                   │
                                        ▼                   ▼
                                 ┌─────────────┐     ┌─────────────┐
                                 │  See '='    │     │  See '='    │
                                 │             │     │             │
                                 │  Emit +%=   │     │  Emit +|=   │
                                 └─────────────┘     └─────────────┘
                                        │                   │
                         ┌──────────────┴───────────────────┘
                         │  See anything else
                         ▼
                  ┌─────────────┐
                  │  Emit +%    │  (or +|)
                  │  or just +  │
                  └─────────────┘
```

### Code for Plus States

```zig
.plus => {
    self.index += 1;
    switch (self.buffer[self.index]) {
        '=' => {
            self.index += 1;
            result.tag = .plus_equal;      // +=
        },
        '%' => continue :state .plus_percent,
        '|' => continue :state .plus_pipe,
        '+' => {
            self.index += 1;
            result.tag = .plus_plus;       // ++
        },
        else => result.tag = .plus,        // just +
    }
},

.plus_percent => {
    self.index += 1;
    switch (self.buffer[self.index]) {
        '=' => {
            self.index += 1;
            result.tag = .plus_percent_equal;  // +%=
        },
        else => result.tag = .plus_percent,    // +%
    }
},

.plus_pipe => {
    self.index += 1;
    switch (self.buffer[self.index]) {
        '=' => {
            self.index += 1;
            result.tag = .plus_pipe_equal;     // +|=
        },
        else => result.tag = .plus_pipe,       // +|
    }
},
```

## String Literal State Machine

Strings have their own mini state machine to handle escape sequences:

```
                         ┌─────────────────────────────────────┐
                         │            SAW '"'                   │
                         │                                      │
                         │     Enter STRING_LITERAL state       │
                         └─────────────────────────────────────┘
                                          │
                                          ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                           STRING_LITERAL STATE                                 │
│                                                                                │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌────────────┐  │
│   │  See '\\'    │    │  See '"'     │    │  See '\n'    │    │  See other │  │
│   │              │    │              │    │              │    │            │  │
│   │  Go to       │    │  END STRING  │    │  ERROR!      │    │  Stay in   │  │
│   │  BACKSLASH   │    │  Emit token  │    │  No newlines │    │  state     │  │
│   └──────────────┘    └──────────────┘    └──────────────┘    └────────────┘  │
│          │                                                           │         │
│          ▼                                                           │         │
│   ┌──────────────────────────────────────────────────────────────────┘         │
│   │  STRING_LITERAL_BACKSLASH STATE                                            │
│   │                                                                            │
│   │  Valid escapes: \n \r \t \\ \" \' \x.. \u{..}                              │
│   │                                                                            │
│   │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐                        │
│   │  │ See 'n' │  │ See 'x' │  │ See 'u' │  │ Other   │                        │
│   │  │ \n      │  │ \xNN    │  │ \u{...} │  │ ERROR   │                        │
│   │  └─────────┘  └─────────┘  └─────────┘  └─────────┘                        │
│   │       │            │            │                                          │
│   │       └────────────┴────────────┴──────────▶ Back to STRING_LITERAL        │
│   └────────────────────────────────────────────────────────────────────────────┘
└────────────────────────────────────────────────────────────────────────────────┘
```

### Example: Tokenizing `"hello\nworld"`

```
Input: "hello\nworld"

Step 1: See '"' → Enter STRING_LITERAL
        "hello\nworld"
         ^

Step 2-6: See 'h','e','l','l','o' → Stay in STRING_LITERAL
          "hello\nworld"
               ^

Step 7: See '\\' → Go to STRING_LITERAL_BACKSLASH
        "hello\nworld"
              ^

Step 8: See 'n' → Valid escape! Back to STRING_LITERAL
        "hello\nworld"
               ^

Step 9-13: See 'w','o','r','l','d' → Stay in STRING_LITERAL
           "hello\nworld"
                      ^

Step 14: See '"' → END! Emit string_literal token
         "hello\nworld"
                      ^

Result: Token { .tag = .string_literal, .loc = { 0, 14 } }
```

## Number Parsing State Machine

Numbers are complex because of all the formats:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         NUMBER PARSING                                       │
│                                                                              │
│   Start: See '0'-'9'                                                         │
│                                                                              │
│   ┌─────────┐                                                                │
│   │   INT   │◀────────────────────────────────────────────────────────┐      │
│   └─────────┘                                                         │      │
│        │                                                              │      │
│        ├──── See '0'-'9', '_' ─────────────────────────────────────────┘      │
│        │     (continue reading digits)                                       │
│        │                                                                     │
│        ├──── See '.' ──────────────────▶ ┌─────────────┐                     │
│        │                                 │ INT_PERIOD  │                     │
│        │                                 └─────────────┘                     │
│        │                                        │                            │
│        │                                        ├─── See '0'-'9' ──▶ FLOAT   │
│        │                                        │                            │
│        │                                        └─── See '.' ──▶ '..' token  │
│        │                                             (not a float!)          │
│        │                                                                     │
│        ├──── See 'e','E' ──────────────▶ ┌─────────────┐                     │
│        │     (exponent)                  │INT_EXPONENT │                     │
│        │                                 └─────────────┘                     │
│        │                                        │                            │
│        │                                        └─── See '+','-' ──▶ FLOAT   │
│        │                                                                     │
│        ├──── See 'b' ──────────────────▶ Binary: 0b1010                      │
│        │     (after 0)                                                       │
│        │                                                                     │
│        ├──── See 'o' ──────────────────▶ Octal: 0o755                        │
│        │     (after 0)                                                       │
│        │                                                                     │
│        └──── See 'x' ──────────────────▶ Hex: 0xFF                           │
│              (after 0)                                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Number Examples

```
Decimal:     42         → .number_literal
             1_000_000  → .number_literal (underscores allowed!)

Binary:      0b1010     → .number_literal
             0b1111_0000→ .number_literal

Octal:       0o755      → .number_literal

Hex:         0xFF       → .number_literal
             0xDEAD_BEEF→ .number_literal

Float:       3.14       → .number_literal
             1.0e-10    → .number_literal
             0x1.0p10   → .number_literal (hex float!)
```

## Comment State Machine

Comments have a decision tree for the different types:

```
             ┌─────────────────────────────────────────┐
             │              SAW '/'                     │
             └─────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
       ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
       │  See '/'    │ │  See '='    │ │  See other  │
       │             │ │             │ │             │
       │  COMMENT!   │ │  Emit /=    │ │  Emit /     │
       └─────────────┘ └─────────────┘ └─────────────┘
              │
              ▼
       ┌─────────────────────────────────────────────┐
       │          LINE_COMMENT_START                  │
       │                                              │
       │  What kind of comment?                       │
       └─────────────────────────────────────────────┘
              │
              ├──── See '!' ──────▶ //! Container doc comment
              │                     (module-level docs)
              │
              ├──── See '/' ──────▶ Maybe /// doc comment?
              │                            │
              │                            ├── See '/' ──▶ //// Regular comment
              │                            │               (too many slashes)
              │                            │
              │                            └── Other ──▶ /// Doc comment
              │                                          (for declarations)
              │
              └──── Other ────────▶ // Regular comment
                                    (skip until newline)
```

### Comment Examples

```zig
// Regular comment           → Skipped entirely (no token)

/// Documentation comment    → .doc_comment
/// for the next item

//! Module-level docs        → .container_doc_comment
//! Describes the file

//// Too many slashes        → Regular comment (skipped)
```

## Token Types Reference

Zig has 185 token types. Here are the categories:

### Literals
```zig
.identifier              // foo, Bar, _internal
.string_literal          // "hello"
.multiline_string_literal_line  // \\multiline string
.char_literal            // 'x'
.number_literal          // 42, 0xFF, 3.14
```

### Operators (showing state machine complexity)
```
Single char:    +  -  *  /  =  !  <  >  &  |  ^  %  ~
                │  │  │  │  │  │  │  │  │  │  │  │  │
                │  │  │  │  │  │  │  │  │  │  │  │  └── ~  (bit not)
                │  │  │  │  │  │  │  │  │  │  │  │
                │  │  │  │  │  │  │  │  │  │  │  └───── %  %=
                │  │  │  │  │  │  │  │  │  │  │
                │  │  │  │  │  │  │  │  │  │  └──────── ^  ^=
                │  │  │  │  │  │  │  │  │  │
                │  │  │  │  │  │  │  │  │  └─────────── |  |=  ||
                │  │  │  │  │  │  │  │  │
                │  │  │  │  │  │  │  │  └──────────────&  &=
                │  │  │  │  │  │  │  │
                │  │  │  │  │  │  │  └─────────────────>  >=  >>  >>=
                │  │  │  │  │  │  │
                │  │  │  │  │  │  └────────────────────<  <=  <<  <<=  <<|  <<|=
                │  │  │  │  │  │
                │  │  │  │  │  └───────────────────────!  !=
                │  │  │  │  │
                │  │  │  │  └──────────────────────────=  ==  =>
                │  │  │  │
                │  │  │  └─────────────────────────────/  /=  // (comment)
                │  │  │
                │  │  └────────────────────────────────*  *=  *%  *%=  *|  *|=  **
                │  │
                │  └───────────────────────────────────-  -=  -%  -%=  -|  -|=
                │
                └──────────────────────────────────────+  +=  +%  +%=  +|  +|=  ++
```

### Keywords (59 total)
```zig
// Control flow
if, else, switch, while, for, break, continue, return

// Declarations
const, var, fn, struct, enum, union, opaque, test

// Error handling
try, catch, error, errdefer

// Memory
defer, comptime, inline, noalias, volatile

// Types
anytype, anyframe, type

// Boolean/logic
and, or, orelse, true, false

// Special
pub, extern, export, align, packed, threadlocal,
linksection, callconv, addrspace, allowzero,
suspend, resume, nosuspend, unreachable, undefined,
null, asm, noinline
```

## The Tokenizer Structure

```zig
pub const Tokenizer = struct {
    buffer: [:0]const u8,  // Null-terminated source code
    index: usize,          // Current position

    pub fn init(buffer: [:0]const u8) Tokenizer {
        // Skip UTF-8 BOM if present
        return .{
            .buffer = buffer,
            .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0,
        };
    }
};
```

Note that the source must be null-terminated (`[:0]const u8`). This allows the tokenizer to detect end-of-file without bounds checking.

## The Main Tokenization Loop

The `next()` function is the heart of the tokenizer:

```zig
pub fn next(self: *Tokenizer) Token {
    var result: Token = .{
        .tag = undefined,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    state: switch (State.start) {
        .start => switch (self.buffer[self.index]) {
            0 => {
                // End of file
                if (self.index == self.buffer.len) {
                    return .{
                        .tag = .eof,
                        .loc = .{ .start = self.index, .end = self.index },
                    };
                } else {
                    // Null byte in middle of file
                    continue :state .invalid;
                }
            },

            // Skip whitespace
            ' ', '\n', '\t', '\r' => {
                self.index += 1;
                result.loc.start = self.index;
                continue :state .start;
            },

            // String literal
            '"' => {
                result.tag = .string_literal;
                continue :state .string_literal;
            },

            // Identifier or keyword
            'a'...'z', 'A'...'Z', '_' => {
                result.tag = .identifier;
                continue :state .identifier;
            },

            // Operators
            '+' => continue :state .plus,
            '-' => continue :state .minus,
            '*' => continue :state .asterisk,
            '/' => continue :state .slash,

            // ... more cases
        },

        // ... more states
    }

    result.loc.end = self.index;
    return result;
}
```

The `continue :state` construct is Zig's **labeled switch continue**, which efficiently jumps to another state without function call overhead.

## Full Tokenization Example

Let's trace the complete tokenization of a simple statement:

```
Input: "var x: i32 = -5;"

┌─────────────────────────────────────────────────────────────────────────────┐
│ Step │ Char │ State          │ Action                    │ Token Emitted    │
├─────────────────────────────────────────────────────────────────────────────┤
│  1   │ 'v'  │ start          │ → identifier              │                  │
│  2   │ 'a'  │ identifier     │ continue                  │                  │
│  3   │ 'r'  │ identifier     │ continue                  │                  │
│  4   │ ' '  │ identifier     │ check keyword → YES       │ .keyword_var     │
├─────────────────────────────────────────────────────────────────────────────┤
│  5   │ ' '  │ start          │ skip whitespace           │                  │
│  6   │ 'x'  │ start          │ → identifier              │                  │
│  7   │ ':'  │ identifier     │ emit, not keyword         │ .identifier      │
├─────────────────────────────────────────────────────────────────────────────┤
│  8   │ ':'  │ start          │ single char token         │ .colon           │
├─────────────────────────────────────────────────────────────────────────────┤
│  9   │ ' '  │ start          │ skip whitespace           │                  │
│ 10   │ 'i'  │ start          │ → identifier              │                  │
│ 11   │ '3'  │ identifier     │ continue                  │                  │
│ 12   │ '2'  │ identifier     │ continue                  │                  │
│ 13   │ ' '  │ identifier     │ emit, not keyword         │ .identifier      │
├─────────────────────────────────────────────────────────────────────────────┤
│ 14   │ ' '  │ start          │ skip whitespace           │                  │
│ 15   │ '='  │ start          │ → equal state             │                  │
│ 16   │ ' '  │ equal          │ not '=', emit             │ .equal           │
├─────────────────────────────────────────────────────────────────────────────┤
│ 17   │ ' '  │ start          │ skip whitespace           │                  │
│ 18   │ '-'  │ start          │ → minus state             │                  │
│ 19   │ '5'  │ minus          │ not '-=%|', emit          │ .minus           │
├─────────────────────────────────────────────────────────────────────────────┤
│ 20   │ '5'  │ start          │ → int state               │                  │
│ 21   │ ';'  │ int            │ emit number               │ .number_literal  │
├─────────────────────────────────────────────────────────────────────────────┤
│ 22   │ ';'  │ start          │ single char token         │ .semicolon       │
├─────────────────────────────────────────────────────────────────────────────┤
│ 23   │ EOF  │ start          │ end of input              │ .eof             │
└─────────────────────────────────────────────────────────────────────────────┘

Final token stream:
[.keyword_var] [.identifier] [.colon] [.identifier] [.equal] [.minus] [.number_literal] [.semicolon] [.eof]
     "var"          "x"         ":"       "i32"        "="       "-"         "5"            ";"
```

## Error Recovery and Invalid Tokens (Deep Dive)

The tokenizer must handle malformed input gracefully. Instead of crashing, it produces `.invalid` tokens and continues parsing. This allows the compiler to report multiple errors in one pass.

### What Causes Invalid Tokens?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CAUSES OF INVALID TOKENS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. ILLEGAL CHARACTERS                                                       │
│     ───────────────────                                                      │
│     #  `  $  ~  etc.        Characters not in Zig's grammar                 │
│                                                                              │
│  2. NULL BYTES IN SOURCE                                                     │
│     ────────────────────                                                     │
│     "hello\x00world"        Null byte in middle of file                     │
│                             (valid only at EOF)                             │
│                                                                              │
│  3. UNTERMINATED STRINGS                                                     │
│     ────────────────────                                                     │
│     "hello                  String that never closes                        │
│     "hello\                 Escape at end of string                         │
│     "hello                  Newline in string literal                       │
│     world"                                                                  │
│                                                                              │
│  4. UNTERMINATED CHAR LITERALS                                              │
│     ──────────────────────────                                               │
│     'c                      Missing closing quote                           │
│     '                       Empty char literal start                        │
│     '\                      Escape at end                                   │
│                                                                              │
│  5. INVALID ESCAPE SEQUENCES                                                │
│     ────────────────────────                                                 │
│     "\q"                    Invalid escape char                             │
│     '\u'                    Incomplete unicode escape                       │
│                                                                              │
│  6. CONTROL CHARACTERS                                                       │
│     ──────────────────                                                       │
│     0x00-0x1F               Control chars in strings/comments               │
│     0x7F (DEL)              Delete character                                │
│                                                                              │
│  7. INVALID TAB/CR PLACEMENT                                                │
│     ────────────────────────                                                 │
│     //\t comment            Tab in comment (ambiguous rendering)            │
│     // text\r               Bare CR (not followed by \n)                    │
│                                                                              │
│  8. INVALID @ SEQUENCES                                                      │
│     ───────────────────                                                      │
│     @()                     @ not followed by identifier or "               │
│     @0abc                   @ followed by digit                             │
│                                                                              │
│  9. INVALID OPERATOR SEQUENCES                                              │
│     ──────────────────────────                                               │
│     .**                     Period-asterisk-asterisk is invalid             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The Invalid State (Actual Source Code)

Here's the actual code from `lib/std/zig/tokenizer.zig` that handles invalid tokens:

```zig
.invalid => {
    self.index += 1;
    switch (self.buffer[self.index]) {
        0 => if (self.index == self.buffer.len) {
            result.tag = .invalid;
        } else {
            continue :state .invalid;  // Null in middle of file
        },
        '\n' => result.tag = .invalid,  // Newline ends invalid token
        else => continue :state .invalid,  // Keep consuming bad chars
    }
},
```

Key insight: **Invalid tokens extend until a newline or EOF**. This groups related errors together.

### How Different Errors Enter Invalid State

```zig
// From START state - illegal character
.start => switch (self.buffer[self.index]) {
    // ... valid cases ...
    else => continue :state .invalid,  // Unknown char → invalid
},

// From SAW_AT_SIGN - @ not followed by valid sequence
.saw_at_sign => switch (self.buffer[self.index]) {
    0, '\n' => result.tag = .invalid,           // @ at EOL
    '"' => { /* valid: @"identifier" */ },
    'a'...'z', 'A'...'Z', '_' => { /* valid: @builtin */ },
    else => continue :state .invalid,           // @# or @0 etc.
},

// From STRING_LITERAL - problematic content
.string_literal => switch (self.buffer[self.index]) {
    0 => {
        if (self.index != self.buffer.len) {
            continue :state .invalid;  // Null byte in string
        } else {
            result.tag = .invalid;     // Unterminated string at EOF
        }
    },
    '\n' => result.tag = .invalid,     // Newline in string = error
    0x01...0x09, 0x0b...0x1f, 0x7f => {
        continue :state .invalid;       // Control characters
    },
    // ... valid cases ...
},

// From BACKSLASH - single \ not followed by valid escape start
.backslash => switch (self.buffer[self.index]) {
    0 => result.tag = .invalid,         // \ at EOF
    '\\' => { /* valid: multiline string \\ */ },
    '\n' => result.tag = .invalid,      // \ then newline
    else => continue :state .invalid,   // \ followed by invalid
},
```

### Visual Invalid Token State Machine

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    INVALID TOKEN STATE MACHINE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                          ENTRY POINTS                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Unknown    │  │  Null byte   │  │  Control     │  │  Invalid @   │     │
│  │   character  │  │  in source   │  │  character   │  │  sequence    │     │
│  │   (#, `, $)  │  │  (\x00)      │  │  (0x01-0x1f) │  │  (@0, @#)    │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                 │                 │                 │              │
│         └─────────────────┴─────────────────┴─────────────────┘              │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         INVALID STATE                                  │  │
│  │                                                                        │  │
│  │   ┌────────────────────────────────────────────────────────────────┐  │  │
│  │   │                     CONSUME LOOP                                │  │  │
│  │   │                                                                 │  │  │
│  │   │   See any character except '\n' or '\0' at EOF                 │  │  │
│  │   │            │                                                    │  │  │
│  │   │            ▼                                                    │  │  │
│  │   │   index++, continue :state .invalid                            │  │  │
│  │   │            │                                                    │  │  │
│  │   │            └──────────────────────────────────┐                │  │  │
│  │   │                                               │                │  │  │
│  │   │   ┌─────────────────────────────────────────────────────────┐  │  │  │
│  │   │   │  KEEP CONSUMING until we see:                           │  │  │  │
│  │   │   │                                                         │  │  │  │
│  │   │   │    '#' '$' '@' '!' '%' ...  ◀── Keep going             │  │  │  │
│  │   │   │                                                         │  │  │  │
│  │   └───┴─────────────────────────────────────────────────────────┘  │  │
│  │                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│              ┌─────────────────────┴─────────────────────┐                   │
│              │                                           │                   │
│              ▼                                           ▼                   │
│  ┌──────────────────────────┐             ┌──────────────────────────┐      │
│  │     See '\n' (newline)   │             │    See '\0' at EOF       │      │
│  │                          │             │                          │      │
│  │  result.tag = .invalid   │             │  result.tag = .invalid   │      │
│  │  EMIT TOKEN & RETURN     │             │  EMIT TOKEN & RETURN     │      │
│  │                          │             │                          │      │
│  │  Ready for next token    │             │  Parser sees .invalid    │      │
│  │  on new line             │             │  then .eof               │      │
│  └──────────────────────────┘             └──────────────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Example 1: Illegal Character

```
Input: "const #bad = 5;"
              ^
              illegal char '#'

┌──────────────────────────────────────────────────────────────────────────────────┐
│ Index │ Char │ State      │ Action                                │ Result       │
├──────────────────────────────────────────────────────────────────────────────────┤
│   0   │ 'c'  │ start      │ → identifier                          │              │
│   5   │ ' '  │ identifier │ emit "const"                          │ keyword_const│
│   6   │ '#'  │ start      │ Unknown char! → invalid                │              │
│   7   │ 'b'  │ invalid    │ Not '\n' or EOF, continue              │              │
│   8   │ 'a'  │ invalid    │ Not '\n' or EOF, continue              │              │
│   9   │ 'd'  │ invalid    │ Not '\n' or EOF, continue              │              │
│  10   │ ' '  │ invalid    │ Not '\n' or EOF, continue              │              │
│  11   │ '='  │ invalid    │ Not '\n' or EOF, continue              │              │
│  12   │ ' '  │ invalid    │ Not '\n' or EOF, continue              │              │
│  13   │ '5'  │ invalid    │ Not '\n' or EOF, continue              │              │
│  14   │ ';'  │ invalid    │ Not '\n' or EOF, continue              │              │
│  15   │ EOF  │ invalid    │ At EOF! Emit invalid token             │ .invalid     │
├──────────────────────────────────────────────────────────────────────────────────┤
│ Token Stream: [.keyword_const] [.invalid]                                        │
│                    "const"       "#bad = 5;"                                     │
│                                                                                  │
│ Note: The ENTIRE rest of the line became one invalid token!                      │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Example 2: Unterminated String

```
Input: "const s = "hello
        var x = 5;"
                    ^
                    newline inside string

┌──────────────────────────────────────────────────────────────────────────────────┐
│ Index │ Char │ State          │ Action                          │ Result         │
├──────────────────────────────────────────────────────────────────────────────────┤
│   0   │ 'c'  │ start          │ → identifier                    │                │
│  ...  │      │                │                                 │ keyword_const  │
│   8   │ '='  │ start          │ → equal                         │ .equal         │
│  10   │ '"'  │ start          │ → string_literal                │                │
│  11   │ 'h'  │ string_literal │ continue                        │                │
│  ...  │      │                │                                 │                │
│  16   │ '\n' │ string_literal │ NEWLINE IN STRING! → .invalid   │ .invalid       │
├──────────────────────────────────────────────────────────────────────────────────┤
│  17   │ ' '  │ start          │ skip whitespace                 │                │
│  ...  │      │                │ (recovery complete!)            │                │
│       │      │                │ Continues normally:             │                │
│       │      │                │ var, x, =, 5, ;                 │                │
├──────────────────────────────────────────────────────────────────────────────────┤
│ Token Stream: [const] [s] [=] [.invalid] [var] [x] [=] [5] [;]                   │
│                                    │                                             │
│                                    └── Just the bad string, rest recovered       │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Example 3: Multiple Errors

```
Input: "const @# = `test`;"

┌──────────────────────────────────────────────────────────────────────────────────┐
│                         MULTIPLE ERROR RECOVERY                                   │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│ Error 1: @# is invalid (@ not followed by identifier or ")                      │
│ Error 2: ` is an illegal character                                              │
│                                                                                  │
│ Position:  const @# = `test`;                                                    │
│                   ^^   ^^^^^                                                     │
│                   │    │                                                         │
│                   │    └── Second invalid token                                  │
│                   └── First invalid token                                        │
│                                                                                  │
│ Token Stream:                                                                    │
│   [.keyword_const] [.invalid] [.equal] [.invalid] [.semicolon]                  │
│        "const"         "@#"      "="     "`test`"      ";"                      │
│                                                                                  │
│ The tokenizer recovered TWICE and still got valid tokens in between!            │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Example 4: Control Characters

```
Input: "const s = "hel\x00lo";"    (null byte embedded)

┌──────────────────────────────────────────────────────────────────────────────────┐
│ Index │ Char  │ State          │ Action                          │ Result        │
├──────────────────────────────────────────────────────────────────────────────────┤
│  10   │  '"'  │ start          │ → string_literal                │               │
│  11   │  'h'  │ string_literal │ continue                        │               │
│  12   │  'e'  │ string_literal │ continue                        │               │
│  13   │  'l'  │ string_literal │ continue                        │               │
│  14   │ 0x00  │ string_literal │ NULL BYTE! Not at EOF!          │               │
│       │       │                │ → .invalid state                │               │
│  15   │  'l'  │ invalid        │ continue                        │               │
│  16   │  'o'  │ invalid        │ continue                        │               │
│  17   │  '"'  │ invalid        │ continue (still invalid!)       │               │
│  18   │  ';'  │ invalid        │ continue                        │               │
│  19   │ EOF   │ invalid        │ At EOF, emit                    │ .invalid      │
├──────────────────────────────────────────────────────────────────────────────────┤
│ Note: Once in invalid state, even valid chars like " don't escape it!           │
│       Only '\n' or EOF can end an invalid token.                                 │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Example 5: Invalid Tab in Comment

```
Input: "// comment\twith tab"

┌──────────────────────────────────────────────────────────────────────────────────┐
│ Index │ Char  │ State         │ Action                          │ Result         │
├──────────────────────────────────────────────────────────────────────────────────┤
│   0   │  '/'  │ start         │ → slash                         │                │
│   1   │  '/'  │ slash         │ → line_comment_start            │                │
│   2   │  ' '  │ line_comment  │ continue                        │                │
│  ...  │       │               │                                 │                │
│  10   │ '\t'  │ line_comment  │ TAB! Control char in comment    │                │
│       │       │               │ → .invalid state                │                │
│  ...  │       │               │ consume rest of line            │                │
│  19   │ EOF   │ invalid       │ emit                            │ .invalid       │
├──────────────────────────────────────────────────────────────────────────────────┤
│ Why tabs are invalid in comments:                                                │
│   - Ambiguous rendering (how many spaces is a tab?)                             │
│   - Zig spec requires unambiguous source representation                         │
│   - Use spaces instead, or zig fmt will fix it                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Special Case: invalid_periodasterisks

There's one special "structured invalid" token:

```zig
// This is specifically detected and given its own tag
.period_asterisk => switch (self.buffer[self.index]) {
    '*' => result.tag = .invalid_periodasterisks,  // .**
    else => result.tag = .period_asterisk,         // .*
},
```

Why? The sequence `.**` looks like it might be valid but isn't:

```
"ptr".**    ← Looks like pointer dereference but extra *
             Results in .invalid_periodasterisks

This allows better error messages than generic .invalid
```

### Recovery Properties

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    INVALID TOKEN GUARANTEES                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. BOUNDED SCOPE                                                            │
│     ─────────────                                                            │
│     Invalid tokens always end at:                                            │
│       • Newline ('\n')                                                       │
│       • End of file (EOF)                                                    │
│                                                                              │
│     This means: errors on one line don't affect the next line               │
│                                                                              │
│  2. MONOTONIC PROGRESS                                                       │
│     ──────────────────                                                       │
│     self.index always increases                                              │
│     Tokenizer never gets stuck in infinite loop                             │
│                                                                              │
│  3. NO CASCADING                                                             │
│     ─────────────                                                            │
│     After emitting .invalid, returns to .start state                        │
│     Ready to tokenize next valid content                                    │
│                                                                              │
│  4. POSITION PRESERVATION                                                    │
│     ─────────────────────                                                    │
│     Invalid token has loc.start and loc.end                                 │
│     Error reporter can show exactly what was invalid                        │
│                                                                              │
│  5. TESTABLE                                                                 │
│     ────────                                                                 │
│     Token stream always valid (may contain .invalid tokens)                 │
│     Parser can handle .invalid gracefully                                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### How the Parser Handles Invalid Tokens

When the parser encounters `.invalid`:

```zig
// In parser (simplified)
fn parseExpression() Error!*Node {
    const token = tokenizer.next();

    switch (token.tag) {
        .invalid => {
            // Report error with source location
            try errors.add(.{
                .tag = .invalid_token,
                .loc = token.loc,
            });
            // Skip and try to continue
            return error.InvalidToken;
        },
        // ... normal cases
    }
}
```

This allows the compiler to:
1. Report the error with precise location
2. Continue parsing to find more errors
3. Give the user multiple error messages in one compile

### Test Cases from the Tokenizer

The tokenizer has extensive tests for invalid scenarios:

```zig
test "invalid token characters" {
    try testTokenize("#", &.{.invalid});
    try testTokenize("`", &.{.invalid});
    try testTokenize("'c", &.{.invalid});      // Unterminated char
    try testTokenize("'", &.{.invalid});       // Empty char start
    try testTokenize("''", &.{.char_literal}); // Empty char is valid!
    try testTokenize("'\n'", &.{ .invalid, .invalid });
}

test "invalid literal/comment characters" {
    try testTokenize("\"\x00\"", &.{.invalid});  // Null in string
    try testTokenize("//\x00", &.{.invalid});    // Null in comment
    try testTokenize("//\x1f", &.{.invalid});    // Control char
    try testTokenize("//\x7f", &.{.invalid});    // DEL char
}

test "invalid tabs and carriage returns" {
    try testTokenize("//\t", &.{.invalid});      // Tab in comment
    try testTokenize("//\r", &.{.invalid});      // Bare CR
    try testTokenize("//\r\n", &.{});            // CR+LF is valid
}

test "null byte before eof" {
    try testTokenize("123 \x00 456", &.{ .number_literal, .invalid });
    try testTokenize("\x00", &.{.invalid});
}

test "invalid builtin identifiers" {
    try testTokenize("@()", &.{.invalid});      // @ then (
    try testTokenize("@0()", &.{.invalid});     // @ then digit
}

test "invalid token with unfinished escape" {
    try testTokenize("\"\\", &.{.invalid});     // String with \ at EOF
    try testTokenize("'\\", &.{.invalid});      // Char with \ at EOF
}
```

## Performance Considerations

The tokenizer is designed for speed:

```
┌─────────────────────────────────────────────────────────────────┐
│                    PERFORMANCE FEATURES                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. SINGLE-PASS                                                  │
│     ┌─▶ Each character examined exactly once                     │
│     │   No backtracking                                          │
│     │                                                            │
│  2. NO ALLOCATIONS                                               │
│     │   Tokens are just (start, end) pairs                       │
│     │   Reference original source buffer                         │
│     │                                                            │
│  3. BRANCH PREDICTION                                            │
│     │   Common cases (whitespace, identifiers) first             │
│     │   Hot paths optimized                                      │
│     │                                                            │
│  4. NULL-TERMINATED SOURCE                                       │
│     │   No bounds checking on every character                    │
│     │   EOF detection is free                                    │
│     │                                                            │
│  5. LABELED SWITCH CONTINUE                                      │
│     └── State transitions without function call overhead         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Try It Yourself

You can explore how the tokenizer works by dumping the tokens for any Zig file:

```bash
# See all tokens for a file
zig ast-check --dump-tokens your_file.zig
```

This is a great way to understand how Zig breaks down your code into its fundamental pieces.

---

## Further Reading

For deeper exploration of Zig's tokenizer:

- **[Zig Tokenizer](https://mitchellh.com/zig/tokenizer)** by Mitchell Hashimoto - An excellent deep dive into the tokenizer implementation, state machine design, and performance optimizations.

- **[Zig GitHub Wiki Glossary](https://github.com/ziglang/zig/wiki/Glossary)** - Official terminology for compiler internals.

- **Source Code**: [`lib/std/zig/Tokenizer.zig`](https://github.com/ziglang/zig/blob/master/lib/std/zig/Tokenizer.zig) - The actual implementation (1,769 lines of elegant Zig).

---

## Conclusion

Zig's tokenizer is a masterclass in hand-crafted compiler engineering. By using a state machine with labeled switch continues, it achieves excellent performance while remaining readable and maintainable.

Key takeaways:
- **41 states** handle all of Zig's lexical complexity
- **185 token types** from keywords to complex operators
- **Zero allocations** - tokens reference the original source
- **Single pass** - each character examined once
- **Error recovery** - continues parsing after invalid input

The tokenizer's job is to produce a flat stream of tokens. In the next article, we'll see how the **Parser** transforms this stream into a tree structure: the **Abstract Syntax Tree (AST)**.

---

**Previous**: [Part 1: Bootstrap Process](./01-bootstrap-process.md)
**Next**: [Part 3: Parser and AST](./03-parser-ast.md)

**Series Index**:
1. [Bootstrap Process](./01-bootstrap-process.md)
2. **Tokenizer** (this article)
3. [Parser and AST](./03-parser-ast.md)
4. [ZIR Generation](./04-zir-generation.md)
5. [Semantic Analysis](./05-sema.md)
6. [AIR and Code Generation](./06-air-codegen.md)
7. [Linking](./07-linking.md)

