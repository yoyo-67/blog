# Zig Compiler Internals Part 3: Parser and AST

*Building trees from tokens with recursive descent*

---

## Introduction

After the tokenizer breaks source code into tokens, the **parser** organizes those tokens into a hierarchical structure called the **Abstract Syntax Tree (AST)**. This tree represents the syntactic structure of the program.

In this article, we'll explore Zig's parser and its memory-efficient AST representation.

---

## What is Parsing? (The Big Picture)

### The Problem: Flat Tokens Aren't Enough

The tokenizer gives us a flat list of tokens:

```
fn, add, (, a, :, u32, ,, b, :, u32, ), u32, {, return, a, +, b, ;, }
```

But this doesn't tell us:
- Which `u32` is a parameter type vs the return type?
- Does `+` apply to `a` and `b`, or something else?
- Where does the function start and end?

### The Solution: A Tree Structure

The parser builds a **tree** that shows relationships:

```
                         fn_decl
                        /       \
                fn_proto         block
               /   |   \            \
          param  param  return     return_stmt
          /  \    /  \    |            |
         a  u32  b  u32  u32          add
                                     /   \
                                    a     b
```

Now we can answer those questions:
- Parameter types are children of `param` nodes
- Return type is a child of `fn_proto`
- `+` creates an `add` node with `a` and `b` as children

### Analogy: Parsing a Sentence

Think of parsing English:

```
"The big dog chased the small cat"
```

A flat word list doesn't show structure. A parse tree does:

```
              Sentence
             /        \
     NounPhrase      VerbPhrase
      /   |   \       /       \
    Det  Adj  Noun  Verb    NounPhrase
     |    |    |     |      /   |   \
   "The" "big" "dog" "chased" Det Adj Noun
                              |   |    |
                           "the" "small" "cat"
```

Programming language parsing works the same way!

---

## The Parser at a Glance

**Location**: `lib/std/zig/Parse.zig` (3,724 lines)

Key characteristics:
- **Hand-written recursive descent** parser
- **Precedence climbing** for expressions
- **Error recovery** for better diagnostics
- **Zero-copy** - references original source

---

## How Recursive Descent Works

### The Core Idea

Each grammar rule becomes a function. The functions call each other, "descending" through the grammar.

```
Grammar Rule                    Parser Function
─────────────────               ─────────────────
FnDecl = "fn" Proto Block  →    fn parseFnDecl()
Block  = "{" Stmts "}"     →    fn parseBlock()
Stmt   = Return | If | ... →    fn parseStatement()
```

### Why "Recursive"?

The magic insight: **the call stack IS the tree structure**.

When functions call other functions:
1. Each function call creates a "frame" on the stack
2. When a function returns, its result goes to its parent
3. This parent-child relationship IS our AST!

```
Code: fn add() { return 1; }

Call Stack (grows down)         AST (grows down)
─────────────────────           ─────────────────
parseFnDecl()              →    fn_decl
  └─ parseFnProto()        →      ├─ fn_proto
  └─ parseBlock()          →      └─ block
       └─ parseStatement() →           └─ return_stmt
            └─ parseExpr() →                └─ literal "1"
```

The recursion "unwinds" naturally:
- `parseExpr()` returns node for "1"
- `parseStatement()` wraps it in "return_stmt", returns that
- `parseBlock()` collects statements, returns "block"
- `parseFnDecl()` combines proto + block, returns "fn_decl"

### Visual Example: Parsing `fn add() {}`

```
Source: fn add() { }

Step 1: parseFnDecl() called
        ┌─────────────────────────────────────┐
        │ See "fn"? Yes → continue            │
        │ Parse prototype → call parseFnProto │
        │ Parse body → call parseBlock        │
        └─────────────────────────────────────┘
                     │
                     ▼
Step 2: parseFnProto() called
        ┌─────────────────────────────────────┐
        │ Eat identifier "add"                │
        │ See "("? Yes → parse params         │
        │ See return type? No → void          │
        └─────────────────────────────────────┘
                     │
                     ▼
Step 3: parseBlock() called
        ┌─────────────────────────────────────┐
        │ See "{"? Yes → continue             │
        │ Parse statements (none here)        │
        │ See "}"? Yes → done                 │
        └─────────────────────────────────────┘
```

The call stack naturally forms the tree structure!

### Simplified Pseudocode

Here's the pattern distilled to its essence:

```
// Each parse function:
// 1. Checks if it should handle current token
// 2. Consumes tokens it recognizes
// 3. Calls other parsers for nested structures
// 4. Returns a node

fn parseFnDecl():
    if not see("fn"): return null    // Not my job
    eat("fn")                         // Consume token

    proto = parseFnProto()            // RECURSE: child parser
    body = parseBlock()               // RECURSE: another child

    return FnDeclNode(proto, body)    // Combine & return

fn parseBlock():
    expect("{")                       // Must have this

    statements = []
    while not see("}"):
        stmt = parseStatement()       // RECURSE: for each stmt
        statements.append(stmt)

    expect("}")
    return BlockNode(statements)

fn parseStatement():
    if see("return"): return parseReturn()   // RECURSE
    if see("if"):     return parseIf()       // RECURSE
    if see("while"):  return parseWhile()    // RECURSE
    // ... etc
```

**Key insight**: The "recursive" part is just that parsers call other parsers. The call stack tracks where we are in the nested structure automatically!

---

## The AST Structure

**Location**: `lib/std/zig/Ast.zig` (4,029 lines)

```zig
pub const Ast = struct {
    source: [:0]const u8,        // Original source code
    tokens: TokenList.Slice,     // All tokens
    nodes: NodeList.Slice,       // All AST nodes
    extra_data: []u32,           // Overflow storage
    mode: Mode = .zig,           // .zig or .zon
    errors: []const Error,       // Parse errors
};
```

### Why Keep the Source?

The AST doesn't copy strings. Identifiers like `add` are just indices pointing back to the source:

```
Source: "fn add(a: u32) u32 { ... }"
         ↑  ↑   ↑  ↑
         0  3   7  10  (byte positions)

Token for "add":
  .tag = .identifier
  .start = 3
  .end = 6

AST node just stores: main_token = 1 (index of "add" token)
```

This saves memory and enables source location tracking.

---

## Node Structure: Compact and Efficient

Every AST node is just 13 bytes:

```zig
pub const Node = struct {
    tag: Tag,             // 1 byte - what kind of node
    main_token: TokenIndex,  // 4 bytes - primary token
    data: Data,           // 8 bytes - node-specific data
};

comptime {
    assert(@sizeOf(Tag) == 1);
    if (!std.debug.runtime_safety) {
        assert(@sizeOf(Data) == 8);
    }
}
```

### Visualizing Node Memory

```
┌─────────────────────────────────────────────────┐
│                   AST Node (13 bytes)           │
├─────────┬───────────────────┬───────────────────┤
│   Tag   │    main_token     │       Data        │
│ 1 byte  │     4 bytes       │     8 bytes       │
├─────────┼───────────────────┼───────────────────┤
│  .add   │        7          │  { lhs=3, rhs=5 } │
│         │   (the "+" token) │                   │
└─────────┴───────────────────┴───────────────────┘
```

### The Data Union

The `Data` field stores different information depending on the node type:

```zig
pub const Data = union {
    node: Index,                              // Single child node
    opt_node: OptionalIndex,                  // Optional child node
    token: TokenIndex,                        // Token reference
    node_and_node: struct { Index, Index },   // Two children
    opt_node_and_opt_node: struct { OptionalIndex, OptionalIndex },
    extra_range: SubRange,                    // Range into extra_data
    // ... more variants
};
```

### Visual: How Data Union Works for Different Node Types

```
┌──────────────────────────────────────────────────────────────┐
│ Node Type: .add  (binary operation)                          │
├──────────────────────────────────────────────────────────────┤
│ Data = .node_and_node = { lhs: 3, rhs: 5 }                   │
│                                                              │
│         add (this node)                                      │
│        /   \                                                 │
│   node[3]  node[5]                                           │
│      a        b                                              │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Node Type: .negation  (unary operation)                      │
├──────────────────────────────────────────────────────────────┤
│ Data = .node = 4                                             │
│                                                              │
│       negation (this node)                                   │
│           |                                                  │
│       node[4]                                                │
│          x                                                   │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Node Type: .identifier  (leaf node)                          │
├──────────────────────────────────────────────────────────────┤
│ Data = .token = 12                                           │
│                                                              │
│       identifier (this node, references token 12)            │
│           |                                                  │
│         (no children - it's a leaf!)                         │
└──────────────────────────────────────────────────────────────┘
```

---

## Node Types: 200+ Varieties

The parser recognizes many node types:

```zig
pub const Tag = enum {
    // Root
    root,

    // Declarations
    test_decl,
    global_var_decl,
    local_var_decl,
    simple_var_decl,
    aligned_var_decl,
    fn_decl,

    // Control flow
    @"if",
    if_simple,
    @"while",
    while_simple,
    while_cont,
    @"for",
    for_simple,
    @"switch",

    // Expressions
    call,
    call_one,           // Optimization: exactly 1 argument
    call_one_comma,
    field_access,
    array_access,
    deref,

    // Binary operators
    add, sub, mul, div,
    bit_and, bit_or, bit_xor,
    bool_and, bool_or,
    equal_equal, bang_equal,
    less_than, greater_than,

    // Unary operators
    bool_not,
    negation,
    address_of,
    @"try",

    // Types
    optional_type,
    array_type,
    ptr_type,

    // Blocks
    block,
    block_two,          // Optimized: 0-2 statements
    block_two_semicolon,

    // ... 200+ total
};
```

### Why So Many Variants?

Notice `call` vs `call_one` vs `call_one_comma`? These optimize common cases:

```
┌─────────────────────────────────────────────────────────────┐
│ Node Variant Selection for Function Calls                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   foo()           → call_one      (0-1 args, fits in Data)  │
│   foo(x)          → call_one      (0-1 args, fits in Data)  │
│   foo(x,)         → call_one_comma (trailing comma)         │
│   foo(x, y)       → call          (2+ args, uses extra_data)│
│   foo(x, y, z)    → call          (2+ args, uses extra_data)│
│                                                             │
│   Most calls have 0-1 arguments, so call_one is very common │
│   and avoids extra_data allocation!                         │
└─────────────────────────────────────────────────────────────┘
```

Same pattern for blocks:

```
┌─────────────────────────────────────────────────────────────┐
│ Node Variant Selection for Blocks                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   {}              → block_two  (0 stmts, fits in Data)      │
│   { x; }          → block_two  (1 stmt, fits in Data)       │
│   { x; y; }       → block_two  (2 stmts, fits in Data)      │
│   { x; y; z; }    → block      (3+ stmts, uses extra_data)  │
│                                                             │
│   Most blocks have 0-2 statements!                          │
└─────────────────────────────────────────────────────────────┘
```

---

## MultiArrayList: Cache-Friendly Storage

The AST uses `std.MultiArrayList` for storage:

```zig
pub const NodeList = std.MultiArrayList(Node);
```

### Traditional: Array-of-Structs (AoS)

```
Memory Layout:
┌──────────────────────────────────────────────────────────────┐
│ Node0          │ Node1          │ Node2          │ ...       │
├────┬─────┬─────┼────┬─────┬─────┼────┬─────┬─────┼───────────┤
│tag │token│data │tag │token│data │tag │token│data │ ...       │
│ 1  │  4  │  8  │ 1  │  4  │  8  │ 1  │  4  │  8  │           │
└────┴─────┴─────┴────┴─────┴─────┴────┴─────┴─────┴───────────┘
```

### Zig's Choice: Struct-of-Arrays (SoA)

```
Memory Layout:
┌─────────────────────────────────────────────────────────────┐
│ tags array:                                                 │
│ ┌────┬────┬────┬────┬────┬────┐                             │
│ │tag0│tag1│tag2│tag3│tag4│... │  All tags contiguous!       │
│ └────┴────┴────┴────┴────┴────┘                             │
├─────────────────────────────────────────────────────────────┤
│ main_tokens array:                                          │
│ ┌─────┬─────┬─────┬─────┬─────┬─────┐                       │
│ │tok0 │tok1 │tok2 │tok3 │tok4 │...  │  All tokens together! │
│ └─────┴─────┴─────┴─────┴─────┴─────┘                       │
├─────────────────────────────────────────────────────────────┤
│ data array:                                                 │
│ ┌──────┬──────┬──────┬──────┬──────┬──────┐                 │
│ │data0 │data1 │data2 │data3 │data4 │...   │  All data here! │
│ └──────┴──────┴──────┴──────┴──────┴──────┘                 │
└─────────────────────────────────────────────────────────────┘
```

### Why SoA is Better for Compilers

```
Scenario: Check all node types in the AST

With AoS (traditional):
┌──────────────────────────────────────────────────────────────┐
│ Cache Line 1: [tag0][token0][data0....][tag1][token1][da...  │
│ Cache Line 2: ...ta1][tag2][token2][data2....][tag3][to...   │
│                                                              │
│ Reading tags requires loading data we don't need!            │
│ Wasted memory bandwidth.                                     │
└──────────────────────────────────────────────────────────────┘

With SoA (Zig's approach):
┌──────────────────────────────────────────────────────────────┐
│ Cache Line 1: [tag0][tag1][tag2][tag3][tag4][tag5][tag6]...  │
│ Cache Line 2: [tag64][tag65][tag66]...                       │
│                                                              │
│ One cache line gives us 64 tags! Much faster iteration.      │
└──────────────────────────────────────────────────────────────┘
```

---

## The Parser Structure

```zig
pub const Parse = struct {
    gpa: Allocator,
    source: []const u8,
    tokens: Ast.TokenList.Slice,
    tok_i: TokenIndex,               // Current token
    errors: std.ArrayList(AstError),
    nodes: Ast.NodeList,             // Growing node list
    extra_data: std.ArrayList(u32),  // Overflow storage
    scratch: std.ArrayList(Node.Index),  // Temporary workspace
};
```

### Visualizing Parser State

```
Source:  fn add(a: u32) u32 { return a; }

Tokens:  [fn] [add] [(] [a] [:] [u32] [)] [u32] [{] [return] [a] [;] [}]
           0    1    2   3   4    5    6    7    8     9     10  11  12

Parser State:
┌─────────────────────────────────────────────────────────────┐
│  tok_i: 4                                                   │
│         ↓                                                   │
│  [fn] [add] [(] [a] [:] [u32] [)] [u32] [{] ...             │
│    0    1    2   3   4    5    6    7    8                  │
│                     ↑                                       │
│              Currently parsing type annotation              │
│                                                             │
│  nodes: [root, fn_decl, fn_proto, param, ...]              │
│  scratch: [param_idx] (building param list)                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Expression Parsing: Precedence Climbing

This is how the parser handles expressions like `1 + 2 * 3`.

### The Problem: Operator Precedence

```
Expression: 1 + 2 * 3

Wrong interpretation (left-to-right):
        +
       / \
      1   2    then  *
                    / \
                result  3

      = (1 + 2) * 3 = 9  ✗ WRONG!

Correct interpretation (precedence-aware):
        +
       / \
      1   *
         / \
        2   3

      = 1 + (2 * 3) = 7  ✓ CORRECT!
```

### The Solution: Precedence Climbing

The core idea is beautifully simple:

> **When you see an operator, ask: "Should I handle this, or let my caller handle it?"**

The answer depends on **precedence** (priority). Higher precedence = binds tighter.

```
Precedence Table:
  +, -  → 60  (lower priority)
  *, /  → 70  (higher priority)

Rule: Only handle operators at or above your "minimum precedence"
```

### The Recursive Insight

Here's why this works:

```
parseExprPrecedence(min_prec):
    1. Parse the first operand (a number, variable, etc.)
    2. Look at the next operator
    3. If operator's precedence >= min_prec:
         - Take the operator
         - RECURSE with min_prec = operator_prec + 1
         - Combine: left OP right
         - Go back to step 2
    4. If operator's precedence < min_prec:
         - STOP! Return what you have
         - Let your CALLER handle this operator
```

**The magic**: By recursing with `prec + 1`, we say "only steal operands if you bind TIGHTER than me."

### Simple Example: `1 + 2 * 3`

```
Start: parseExprPrecedence(min_prec=0)
       I'll accept anything with prec >= 0

  ┌─ Parse "1"
  │  See "+"? prec=60 >= 0 ✓ I'll take it!
  │
  │  Now I need the right side of "+"
  │  RECURSE: parseExprPrecedence(min_prec=61)  ← "beat 60 or give up"
  │     │
  │     │  ┌─ Parse "2"
  │     │  │  See "*"? prec=70 >= 61 ✓ I'll take it!
  │     │  │
  │     │  │  RECURSE: parseExprPrecedence(min_prec=71)
  │     │  │     │
  │     │  │     └─ Parse "3", no more operators
  │     │  │        Return: 3
  │     │  │
  │     │  └─ Combine: 2 * 3
  │     │     No more operators with prec >= 61
  │     │     Return: (2 * 3)
  │     │
  │     └─ Got (2 * 3) as right side of "+"
  │
  └─ Combine: 1 + (2 * 3)
     Return: the whole expression

Result: 1 + (2 * 3) = 7 ✓
```

### Why Does `* `Win Over `+`?

The key is step 3: when `+` recurses, it says "min_prec = 61".

- `*` has prec = 70, and 70 >= 61, so the INNER call grabs `*`
- The inner call builds `2 * 3` and returns it
- The outer call gets `(2 * 3)` as its right operand

If it were `1 * 2 + 3`:

```
  Parse "1"
  See "*"? prec=70, I'll take it
  RECURSE with min_prec=71 for right side
     │
     └─ Parse "2"
        See "+"? prec=60 < 71 ✗ NOT MY JOB!
        Return just "2"

  Combine: 1 * 2
  See "+"? prec=60 >= 0 ✓ I'll take it at the outer level
  Get "3" as right side
  Combine: (1 * 2) + 3

Result: (1 * 2) + 3 = 5 ✓
```

The `+` couldn't "steal" the 2 because it wasn't high-priority enough!

### Pseudocode: Precedence Climbing

Here's the algorithm in simple terms:

```
fn parseExprPrecedence(min_prec):
    // Step 1: Get the left operand (number, variable, etc.)
    left = parsePrimaryExpr()

    // Step 2: Keep eating operators while they're "strong enough"
    while true:
        op = currentToken()
        op_prec = getPrecedence(op)

        // Too weak? Let caller handle it
        if op_prec < min_prec:
            break

        // Strong enough! Consume the operator
        advance()

        // Get right side, but only let STRONGER ops steal it
        right = parseExprPrecedence(op_prec + 1)  // ← THE KEY!

        // Combine into a single node
        left = BinaryNode(op, left, right)

    return left
```

**Why `op_prec + 1`?**

This is the crucial trick:
- `+` has prec 60, so it recurses with min_prec = 61
- `*` has prec 70, so 70 >= 61 means `*` gets grabbed by the inner call
- But `+` has prec 60, so 60 < 61 means `+` is rejected by inner call

The `+1` creates a "precedence barrier" that only higher-precedence operators can cross.

### Complex Example: `1 * 2 + 3 * 4 - 5`

This example shows multiple operators at different precedence levels:

```
Precedence reminder:
  +, -  → 60
  *, /  → 70

Expected result: ((1 * 2) + (3 * 4)) - 5 = (2 + 12) - 5 = 9
```

**Full Walkthrough:**

```
═══════════════════════════════════════════════════════════════════════
CALL 1: parseExprPrecedence(min_prec=0)   "I accept anything"
═══════════════════════════════════════════════════════════════════════

Tokens: [1] [*] [2] [+] [3] [*] [4] [-] [5]
         ↑
Parse "1" → left = 1

Loop iteration 1:
  See "*"? prec=70 >= 0 ✓ I'll handle it
  Consume "*"
  RECURSE for right side...

  ┌─────────────────────────────────────────────────────────────────
  │ CALL 2: parseExprPrecedence(min_prec=71)   "beat 70 or give up"
  │
  │ Tokens: [1] [*] [2] [+] [3] [*] [4] [-] [5]
  │                   ↑
  │ Parse "2" → left = 2
  │
  │ Loop iteration 1:
  │   See "+"? prec=60 < 71 ✗ NOT STRONG ENOUGH!
  │   Break out of loop
  │
  │ RETURN: 2
  └─────────────────────────────────────────────────────────────────

  Got right = 2
  Combine: left = (1 * 2)

Loop iteration 2:
  Tokens: [1] [*] [2] [+] [3] [*] [4] [-] [5]
                       ↑
  See "+"? prec=60 >= 0 ✓ I'll handle it
  Consume "+"
  RECURSE for right side...

  ┌─────────────────────────────────────────────────────────────────
  │ CALL 3: parseExprPrecedence(min_prec=61)   "beat 60 or give up"
  │
  │ Tokens: [1] [*] [2] [+] [3] [*] [4] [-] [5]
  │                           ↑
  │ Parse "3" → left = 3
  │
  │ Loop iteration 1:
  │   See "*"? prec=70 >= 61 ✓ I'll handle it
  │   Consume "*"
  │   RECURSE for right side...
  │
  │   ┌─────────────────────────────────────────────────────────────
  │   │ CALL 4: parseExprPrecedence(min_prec=71)
  │   │
  │   │ Tokens: [1] [*] [2] [+] [3] [*] [4] [-] [5]
  │   │                                 ↑
  │   │ Parse "4" → left = 4
  │   │
  │   │ Loop iteration 1:
  │   │   See "-"? prec=60 < 71 ✗ NOT STRONG ENOUGH!
  │   │   Break out of loop
  │   │
  │   │ RETURN: 4
  │   └─────────────────────────────────────────────────────────────
  │
  │   Got right = 4
  │   Combine: left = (3 * 4)
  │
  │ Loop iteration 2:
  │   See "-"? prec=60 < 61 ✗ NOT STRONG ENOUGH!
  │   Break out of loop
  │
  │ RETURN: (3 * 4)
  └─────────────────────────────────────────────────────────────────

  Got right = (3 * 4)
  Combine: left = ((1 * 2) + (3 * 4))

Loop iteration 3:
  Tokens: [1] [*] [2] [+] [3] [*] [4] [-] [5]
                                       ↑
  See "-"? prec=60 >= 0 ✓ I'll handle it
  Consume "-"
  RECURSE for right side...

  ┌─────────────────────────────────────────────────────────────────
  │ CALL 5: parseExprPrecedence(min_prec=61)
  │
  │ Tokens: [1] [*] [2] [+] [3] [*] [4] [-] [5]
  │                                          ↑
  │ Parse "5" → left = 5
  │
  │ No more operators!
  │ RETURN: 5
  └─────────────────────────────────────────────────────────────────

  Got right = 5
  Combine: left = (((1 * 2) + (3 * 4)) - 5)

No more operators!
RETURN: (((1 * 2) + (3 * 4)) - 5)

═══════════════════════════════════════════════════════════════════════
FINAL AST:
═══════════════════════════════════════════════════════════════════════

                    -
                   / \
                  +   5
                 / \
                *   *
               / \ / \
              1  2 3  4

Evaluation: (1*2) + (3*4) - 5 = 2 + 12 - 5 = 9 ✓
```

**Key Observations:**

```
┌────────────────────────────────────────────────────────────────────┐
│ 1. THE LOOP HANDLES LEFT-TO-RIGHT AT SAME PRECEDENCE               │
│    ────────────────────────────────────────────────────            │
│    "+" and "-" both have prec=60                                   │
│    They're handled by the SAME call (Call 1) in its loop           │
│    This makes them left-associative: (a + b) - c, not a + (b - c)  │
│                                                                     │
│ 2. RECURSION HANDLES HIGHER PRECEDENCE                             │
│    ────────────────────────────────────────────────────            │
│    When "+" recurses with min_prec=61, it can't see "-" (prec=60) │
│    But it CAN see "*" (prec=70), so "*" binds tighter              │
│                                                                     │
│ 3. THE BARRIER PROTECTS OPERANDS                                   │
│    ────────────────────────────────────────────────────            │
│    Call 3 builds (3 * 4), then sees "-" with prec=60               │
│    But Call 3 has min_prec=61, so it can't take "-"                │
│    It returns (3 * 4) and lets Call 1 handle "-"                   │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### The Actual Zig Code

```zig
fn parseExpr(p: *Parse) Error!?Node.Index {
    return p.parseExprPrecedence(0);
}

fn parseExprPrecedence(p: *Parse, min_prec: i32) Error!?Node.Index {
    var node = try p.parsePrefixExpr() orelse return null;
    var banned_prec: i8 = -1;  // For non-associative operators

    while (true) {
        const tok_tag = p.tokenTag(p.tok_i);
        const info = operTable[@intFromEnum(tok_tag)];

        // Stop if precedence too low
        if (info.prec < min_prec) break;

        // Catch chained comparisons: a < b < c
        if (info.prec == banned_prec) {
            return p.fail(.chained_comparison_operators);
        }

        const oper_token = p.nextToken();

        // Parse right-hand side with higher precedence
        const rhs = try p.parseExprPrecedence(info.prec + 1) orelse {
            try p.warn(.expected_expr);
            return node;
        };

        node = try p.addNode(.{
            .tag = info.tag,
            .main_token = oper_token,
            .data = .{ .node_and_node = .{ node, rhs } },
        });

        // Non-associative operators can't chain
        if (info.assoc == Assoc.none) {
            banned_prec = info.prec;
        }
    }

    return node;
}
```

### Two Recursion Patterns Summary

```
┌────────────────────────────────────────────────────────────────────┐
│                    RECURSION IN PARSING                             │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. RECURSIVE DESCENT (parseFnDecl → parseBlock → parseStatement)  │
│     ─────────────────────────────────────────────────────────────  │
│     Different functions call each other                             │
│     Each function handles one grammar rule                          │
│     Call stack = tree structure                                     │
│                                                                     │
│     parseFnDecl()                                                   │
│       └─ parseFnProto()     ← Different function                   │
│       └─ parseBlock()       ← Different function                   │
│            └─ parseStatement()                                      │
│                                                                     │
│  2. PRECEDENCE CLIMBING (parseExprPrecedence calls itself)         │
│     ─────────────────────────────────────────────────────────────  │
│     Same function calls itself with different min_prec              │
│     min_prec controls "who owns the operand"                        │
│     Higher prec = steals operands from lower prec                   │
│                                                                     │
│     parseExprPrecedence(0)                                          │
│       └─ parseExprPrecedence(61)   ← Same function, higher bar     │
│            └─ parseExprPrecedence(71)                               │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### Detailed Trace: Parsing `1 + 2 * 3`

The following shows every step in detail (the simple example above covers the key insight).

```
Precedence Table (higher = binds tighter):
  +, -  → 60
  *, /  → 70

═══════════════════════════════════════════════════════════════
STEP 1: parseExprPrecedence(min_prec=0)
═══════════════════════════════════════════════════════════════

Tokens: [1] [+] [2] [*] [3]
         ↑

Action: parsePrefixExpr() returns node for "1"
        node = Node{.integer_literal, token=0}

Check operator: "+" has prec=60, which >= 0, so continue

═══════════════════════════════════════════════════════════════
STEP 2: Process "+" operator
═══════════════════════════════════════════════════════════════

Tokens: [1] [+] [2] [*] [3]
             ↑

Action: Consume "+", then recurse for RHS with min_prec=61
        (61 because we want tighter-binding operators only)

        ┌─────────────────────────────────────────────────┐
        │ RECURSIVE CALL: parseExprPrecedence(min_prec=61)│
        └─────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════
STEP 3: Inside recursive call (min_prec=61)
═══════════════════════════════════════════════════════════════

Tokens: [1] [+] [2] [*] [3]
                 ↑

Action: parsePrefixExpr() returns node for "2"
        node = Node{.integer_literal, token=2}

Check operator: "*" has prec=70, which >= 61, so continue!

═══════════════════════════════════════════════════════════════
STEP 4: Process "*" operator (still in recursive call)
═══════════════════════════════════════════════════════════════

Tokens: [1] [+] [2] [*] [3]
                     ↑

Action: Consume "*", recurse for RHS with min_prec=71

        ┌─────────────────────────────────────────────────┐
        │ ANOTHER RECURSIVE CALL: parseExprPrecedence(71) │
        └─────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════
STEP 5: Deepest recursive call (min_prec=71)
═══════════════════════════════════════════════════════════════

Tokens: [1] [+] [2] [*] [3]
                         ↑

Action: parsePrefixExpr() returns node for "3"
        node = Node{.integer_literal, token=4}

Check: No more operators (end of expression)
       Return node for "3"

═══════════════════════════════════════════════════════════════
STEP 6: Back in Step 4's call
═══════════════════════════════════════════════════════════════

Got RHS = "3"
Create: mul_node = Node{.mul, lhs="2", rhs="3"}

Check: No more operators with prec >= 61
       Return mul_node

═══════════════════════════════════════════════════════════════
STEP 7: Back in Step 2's call
═══════════════════════════════════════════════════════════════

Got RHS = mul_node (representing 2*3)
Create: add_node = Node{.add, lhs="1", rhs=mul_node}

Check: No more operators
       Return add_node

═══════════════════════════════════════════════════════════════
FINAL RESULT:
═══════════════════════════════════════════════════════════════

        add
       /   \
      1    mul
          /   \
         2     3

Which correctly represents: 1 + (2 * 3)
```

### Visual: The Key Insight

```
Why does this work?

When we see "+" (prec 60), we ask:
  "Parse the RHS, but only if operators have prec > 60"

This means "*" (prec 70) gets grabbed by the inner call:

  Outer call sees: 1 + ???
                       └── Inner call handles: 2 * 3

  Result: 1 + (2 * 3)


If it were "1 * 2 + 3" instead:

  Outer call starts with "1", sees "*" (prec 70)
  Inner call (min_prec=71) sees "2", then "+" (prec 60)
  But 60 < 71, so inner call STOPS and returns just "2"

  Outer continues: has "1 * 2", sees "+" (prec 60)
  60 >= 0, so outer call handles the "+"

  Result: (1 * 2) + 3
```

### Operator Precedence Table

```zig
const operTable = std.enums.directEnumArrayDefault(Token.Tag, OperInfo,
    .{ .prec = -1, .tag = Node.Tag.root }, 0, .{

    .keyword_or   = .{ .prec = 10, .tag = .bool_or },
    .keyword_and  = .{ .prec = 20, .tag = .bool_and },

    // Comparison (non-associative)
    .equal_equal       = .{ .prec = 30, .tag = .equal_equal, .assoc = .none },
    .bang_equal        = .{ .prec = 30, .tag = .bang_equal, .assoc = .none },
    .angle_bracket_left = .{ .prec = 30, .tag = .less_than, .assoc = .none },

    // Bitwise
    .ampersand    = .{ .prec = 40, .tag = .bit_and },
    .pipe         = .{ .prec = 40, .tag = .bit_or },
    .keyword_orelse = .{ .prec = 40, .tag = .@"orelse" },
    .keyword_catch = .{ .prec = 40, .tag = .@"catch" },

    // Arithmetic
    .plus         = .{ .prec = 60, .tag = .add },
    .minus        = .{ .prec = 60, .tag = .sub },
    .asterisk     = .{ .prec = 70, .tag = .mul },
    .slash        = .{ .prec = 70, .tag = .div },
});
```

### Non-Associative Operators (Why `a < b < c` Fails)

```
In Python:  a < b < c  means  (a < b) and (b < c)
In Zig:     a < b < c  is a COMPILE ERROR

Why? It's ambiguous and error-prone. Zig forces explicit grouping.

The parser catches this with `banned_prec`:

Parsing: a < b < c

1. Parse "a", see "<" (prec=30, assoc=none)
2. Set banned_prec = 30
3. Parse RHS "b"
4. See "<" again (prec=30)
5. 30 == banned_prec → ERROR: chained_comparison_operators

This prevents subtle bugs!
```

---

## Parsing Function Declarations: A Complete Example

Let's trace parsing this function:

```zig
fn add(a: u32, b: u32) u32 {
    return a + b;
}
```

### Step 1: Entry Point

```
parseFnDecl() called

Tokens: [fn] [add] [(] [a] [:] [u32] [,] [b] [:] [u32] [)] [u32] [{] ...
         ↑

See "fn"? Yes! Continue parsing.
```

### Step 2: Parse Function Prototype

```
parseFnProto() called

Tokens: [fn] [add] [(] [a] [:] [u32] [,] [b] [:] [u32] [)] [u32] [{]
              ↑

Eat identifier "add" → function name

See "("? Yes! Parse parameter list.
```

### Step 3: Parse Parameters

```
parseParamDeclList() called

┌─────────────────────────────────────────────────────────────┐
│ Parameter 1:                                                │
│                                                             │
│ [a] [:] [u32] [,]                                           │
│  ↑                                                          │
│                                                             │
│ - Identifier: "a"                                           │
│ - See ":"? Yes → parse type                                 │
│ - Type: u32                                                 │
│ - See ","? Yes → more params coming                         │
│                                                             │
│ Create: param_node = { name="a", type=u32 }                 │
│ Add to scratch buffer                                       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Parameter 2:                                                │
│                                                             │
│ [b] [:] [u32] [)]                                           │
│  ↑                                                          │
│                                                             │
│ - Identifier: "b"                                           │
│ - See ":"? Yes → parse type                                 │
│ - Type: u32                                                 │
│ - See ")"? Yes → end of params                              │
│                                                             │
│ Create: param_node = { name="b", type=u32 }                 │
│ Add to scratch buffer                                       │
└─────────────────────────────────────────────────────────────┘

Scratch buffer now: [param_a, param_b]
```

### Step 4: Parse Return Type

```
Tokens: ... [)] [u32] [{] ...
               ↑

parseTypeExpr() called
Returns: identifier_node for "u32"
```

### Step 5: Select Node Variant

This is where Zig's AST optimization shines. The parser doesn't just create "a function node" - it picks the **most compact variant** that can represent this specific function.

#### Background: The 8-Byte Constraint

Remember, every AST node has exactly 8 bytes for its `data` field:

```zig
pub const Node = struct {
    tag: Tag,           // 1 byte  - what kind of node
    main_token: u32,    // 4 bytes - primary token index
    data: Data,         // 8 bytes - THIS IS ALL WE HAVE!
};
```

The `Data` union can hold different things, but always exactly 8 bytes:

```zig
pub const Data = union {
    // Two node indices (4 + 4 = 8 bytes)
    node_and_node: struct { Index, Index },

    // One node + one extra_data index (4 + 4 = 8 bytes)
    node_and_extra: struct { Index, ExtraIndex },

    // Range into extra_data array (4 + 4 = 8 bytes)
    extra_range: struct { start: u32, end: u32 },

    // Two optional nodes (4 + 4 = 8 bytes)
    opt_node_and_opt_node: struct { OptionalIndex, OptionalIndex },
};
```

**The challenge**: How do you fit variable amounts of data into exactly 8 bytes?

#### Background: What is `extra_data`?

When node data exceeds 8 bytes, the overflow goes into a separate array called `extra_data`:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AST STORAGE                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  NODES ARRAY (fixed-size entries):                                   │
│  ┌──────────┬──────────┬──────────┬──────────┐                      │
│  │ Node 0   │ Node 1   │ Node 2   │ Node 3   │ ...                  │
│  │ 13 bytes │ 13 bytes │ 13 bytes │ 13 bytes │                      │
│  └──────────┴──────────┴──────────┴──────────┘                      │
│       │                      │                                       │
│       │                      └─── data points to extra_data ────┐   │
│       │                                                          │   │
│  EXTRA_DATA ARRAY (overflow storage):                            ▼   │
│  ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐            │
│  │  0  │  1  │  2  │  3  │  4  │  5  │  6  │  7  │ ... │            │
│  │param│param│param│align│addr │sect │call │     │     │            │
│  │  a  │  b  │  c  │expr │space│ion  │conv │     │     │            │
│  └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘            │
│                                                                      │
│  Node.data stores an INDEX or RANGE into extra_data                 │
│  Example: { start: 0, end: 3 } means "params are at indices 0,1,2"  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Background: What Are These Optional Expressions?

Zig functions can have advanced attributes that most functions don't use. Let's understand each one from the ground up.

---

##### 1. ALIGNMENT (`align`) - Memory Layout Control

**What is memory alignment?**

RAM is organized like a grid. CPUs read memory most efficiently when data starts at addresses that are multiples of certain numbers (2, 4, 8, 16, etc.).

```
Memory addresses:
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│  0  │  1  │  2  │  3  │  4  │  5  │  6  │  7  │  8  │  9  │ 10  │ 11  │ ...
└─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘

4-byte aligned means: starts at 0, 4, 8, 12, 16...  (multiples of 4)
8-byte aligned means: starts at 0, 8, 16, 24...     (multiples of 8)
16-byte aligned means: starts at 0, 16, 32, 48...   (multiples of 16)
```

**Why does it matter?**

```
┌─────────────────────────────────────────────────────────────────────┐
│ ALIGNED ACCESS (fast):                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ CPU wants to read 4 bytes starting at address 4:                   │
│                                                                     │
│ ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐                  │
│ │  0  │  1  │  2  │  3  │  4  │  5  │  6  │  7  │                  │
│ └─────┴─────┴─────┴─────┼━━━━━┿━━━━━┿━━━━━┿━━━━━┤                  │
│                         │█████│█████│█████│█████│ ← ONE memory read │
│                         └─────┴─────┴─────┴─────┘                   │
│                                                                     │
│ Result: Single memory access, maximum speed!                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ MISALIGNED ACCESS (slow or crashes):                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ CPU wants to read 4 bytes starting at address 3:                   │
│                                                                     │
│ ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐                  │
│ │  0  │  1  │  2  │  3  │  4  │  5  │  6  │  7  │                  │
│ └─────┴─────┴─────┼━━━━━┿━━━━━┿━━━━━┿━━━━━┼─────┘                  │
│                   │█████│█████│█████│█████│                         │
│                   └─────┴─────┴─────┴─────┘                         │
│                         ↑           ↑                               │
│                    spans two memory "chunks"                        │
│                                                                     │
│ Result: CPU must do TWO reads and combine them (2x slower)         │
│         On some CPUs: crashes with "bus error"!                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**When do you use `align()` on functions?**

```zig
// SIMD (Single Instruction Multiple Data) operations
// SSE/AVX instructions require 16/32-byte aligned data
fn processVector(data: *align(16) [4]f32) align(16) void {
    // The function code itself is 16-byte aligned in memory
    // This helps with instruction cache performance
}

// Hot loops that need to be cache-line aligned (64 bytes typically)
fn criticalLoop() align(64) void {
    // Ensures this function starts at a cache line boundary
    // Reduces cache misses when calling frequently
}
```

**Real-world example:**

```zig
const std = @import("std");

// Without align: function might start at any address
fn normalFunc() void {}

// With align(16): function starts at address divisible by 16
fn alignedFunc() align(16) void {}

pub fn main() void {
    std.debug.print("normalFunc at: {*}\n", .{&normalFunc});
    // Might print: normalFunc at: 0x104a3c7

    std.debug.print("alignedFunc at: {*}\n", .{&alignedFunc});
    // Will print: alignedFunc at: 0x104a3d0  (ends in 0 = divisible by 16)
}
```

---

##### 2. CALLING CONVENTION (`callconv`) - How Functions Talk to Each Other

**What is a calling convention?**

When you call a function, the CPU needs to know:
- Where do arguments go? (which registers? the stack?)
- Who saves which registers? (caller or callee?)
- Where does the return value go?
- How do we clean up the stack afterward?

Different systems have different rules. That's a "calling convention."

```
┌─────────────────────────────────────────────────────────────────────┐
│ FUNCTION CALL AT CPU LEVEL                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ High-level code:    result = add(5, 3);                            │
│                                                                     │
│ What actually happens:                                              │
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ CALLER (your code)                                              ││
│ │                                                                 ││
│ │ 1. Put 5 somewhere (register? stack?)    ← WHERE?               ││
│ │ 2. Put 3 somewhere (register? stack?)    ← WHERE?               ││
│ │ 3. Save registers I need later           ← WHICH ONES?          ││
│ │ 4. Jump to add function                                         ││
│ │ 5. Get result from somewhere             ← WHERE?               ││
│ │ 6. Clean up stack                        ← HOW MUCH?            ││
│ └─────────────────────────────────────────────────────────────────┘│
│                          │                                          │
│                          ▼                                          │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │ CALLEE (add function)                                           ││
│ │                                                                 ││
│ │ 1. Get arguments from somewhere          ← WHERE?               ││
│ │ 2. Save registers I'll modify            ← WHICH ONES?          ││
│ │ 3. Do the work                                                  ││
│ │ 4. Put result somewhere                  ← WHERE?               ││
│ │ 5. Restore saved registers                                      ││
│ │ 6. Return to caller                                             ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│ The CALLING CONVENTION answers all the "WHERE?" and "WHICH?" questions
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Common calling conventions:**

```zig
// Default Zig calling convention (optimized, not stable)
fn zigFunc() void {}
// - Zig can pass args in any registers it wants
// - Can change between compiler versions
// - Fastest for Zig-to-Zig calls

// C calling convention (stable, cross-language)
fn cFunc() callconv(.c) void {}
// - Follows the platform's C ABI (Application Binary Interface)
// - On x86-64 Linux: first 6 int args in rdi, rsi, rdx, rcx, r8, r9
// - Required when: calling C libraries, being called from C

// Example: Calling a C library function
extern fn printf(format: [*:0]const u8, ...) callconv(.c) c_int;

pub fn main() void {
    _ = printf("Hello from Zig!\n");  // This works because we matched C's convention
}
```

**More calling conventions:**

```zig
// Naked function - NO prologue/epilogue, you control everything
fn nakedFunc() callconv(.naked) void {
    // No automatic stack setup!
    // No automatic register saving!
    // You must write raw assembly and handle everything yourself
    asm volatile (
        \\mov eax, 42
        \\ret
    );
}
// Used for: bootloaders, context switching, ultra-optimized hot paths

// Interrupt handler - special hardware requirements
fn interruptHandler() callconv(.interrupt) void {
    // Automatically saves ALL registers (hardware requirement)
    // Uses special 'iret' instruction to return
    // Stack is set up differently than normal calls
}
// Used for: keyboard handlers, timer ticks, exceptions, syscalls

// Kernel/System calling convention
fn syscallHandler() callconv(.system) void {
    // Uses the system call convention for your OS
    // Different register usage than .c
}
```

**Why does this matter?**

```
┌─────────────────────────────────────────────────────────────────────┐
│ WITHOUT MATCHING CALLING CONVENTION:                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ C code:        zig_add(5, 3);                                      │
│ C puts:        5 in rdi, 3 in rsi  (C convention)                  │
│                                                                     │
│ Zig code:      fn zig_add(a: i32, b: i32) i32 { return a + b; }    │
│ Zig expects:   a in rax, b in rbx  (Zig convention - hypothetical) │
│                                                                     │
│ Result: Zig reads GARBAGE from rax and rbx!                        │
│         Program crashes or returns wrong answer.                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WITH MATCHING CALLING CONVENTION:                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ C code:        zig_add(5, 3);                                      │
│ C puts:        5 in rdi, 3 in rsi  (C convention)                  │
│                                                                     │
│ Zig code:      export fn zig_add(a: i32, b: i32) callconv(.c) i32 {│
│                    return a + b;                                   │
│                }                                                    │
│ Zig expects:   a in rdi, b in rsi  (C convention - same!)          │
│                                                                     │
│ Result: Works perfectly! Both sides agree on the rules.            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

##### 3. ADDRESS SPACE (`addrspace`) - Different Types of Memory

**What is an address space?**

Most programs think of memory as one big array. But in reality, computers can have multiple types of memory that work differently:

```
┌─────────────────────────────────────────────────────────────────────┐
│ SIMPLE VIEW (what most programmers see):                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─────────────────────────────────────────────────────────────────┐│
│ │                      MEMORY                                     ││
│ │  0x0000 ──────────────────────────────────────────────► 0xFFFF ││
│ │                                                                 ││
│ │  All memory is the same, just different addresses              ││
│ └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ REALITY (GPU / Embedded systems):                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │
│ │  GLOBAL MEMORY  │  │  SHARED MEMORY  │  │  LOCAL MEMORY   │      │
│ │                 │  │                 │  │                 │      │
│ │ - Large (GBs)   │  │ - Small (KBs)   │  │ - Per-thread    │      │
│ │ - Slow          │  │ - Very fast     │  │ - Fastest       │      │
│ │ - All threads   │  │ - Per workgroup │  │ - Private       │      │
│ │   can access    │  │   can share     │  │                 │      │
│ └─────────────────┘  └─────────────────┘  └─────────────────┘      │
│                                                                     │
│ SAME address (e.g., 0x1000) means DIFFERENT things in each space! │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**GPU example (CUDA/OpenCL):**

```zig
// Pointer to global GPU memory (accessible by all threads)
fn processData(data: *addrspace(.global) f32) void {
    // This pointer points to GPU's main memory
    // Slow to access, but large and shared
}

// Pointer to shared memory (fast, but small)
fn fastProcess(cache: *addrspace(.shared) [256]f32) void {
    // This pointer points to on-chip shared memory
    // Very fast, but only 48KB typically
    // Only threads in same workgroup can see it
}

// Pointer to local memory (per-thread)
fn threadLocal(scratch: *addrspace(.local) [16]f32) void {
    // This pointer points to thread-private memory
    // Fastest, but only this thread can access it
}
```

**Embedded systems example:**

```zig
// Memory-mapped I/O register (hardware control)
const GPIO_BASE: *addrspace(.io) volatile u32 = @ptrFromInt(0x4002_0000);

// Flash memory (read-only, persistent)
const FLASH_START: *addrspace(.flash) const u8 = @ptrFromInt(0x0800_0000);

// SRAM (read-write, fast)
const SRAM_START: *addrspace(.sram) u8 = @ptrFromInt(0x2000_0000);

fn blinkLED() void {
    // Writing to GPIO register actually controls hardware!
    // The address space tells the compiler this is special memory
    GPIO_BASE.* = 0x01;  // Turn on LED
}
```

**Why can't we just use regular pointers?**

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE PROBLEM:                                                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ // On a GPU, these are DIFFERENT memory locations:                 │
│                                                                     │
│ var globalPtr: *f32 = getGlobalPtr();   // Points to global memory │
│ var sharedPtr: *f32 = getSharedPtr();   // Points to shared memory │
│                                                                     │
│ // But to the CPU/compiler, they look the same - just *f32!        │
│ // If we accidentally pass globalPtr where sharedPtr is expected:  │
│                                                                     │
│ fn needsShared(ptr: *f32) void { ... }                             │
│ needsShared(globalPtr);  // COMPILES! But wrong memory type!       │
│                                                                     │
│ // GPU will crash or produce garbage results                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ THE SOLUTION - Address Spaces:                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ var globalPtr: *addrspace(.global) f32 = getGlobalPtr();           │
│ var sharedPtr: *addrspace(.shared) f32 = getSharedPtr();           │
│                                                                     │
│ fn needsShared(ptr: *addrspace(.shared) f32) void { ... }          │
│ needsShared(globalPtr);  // COMPILE ERROR! Type mismatch!          │
│ needsShared(sharedPtr);  // OK                                      │
│                                                                     │
│ The compiler catches the bug at compile time!                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

##### 4. LINKER SECTION (`linksection`) - Where Code Lives in the Binary

**What is linking?**

After the compiler creates object files, the linker combines them into an executable. The linker organizes the binary into "sections":

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXECUTABLE FILE LAYOUT:                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─────────────────────────────────────┐                            │
│ │           HEADERS                    │  Metadata about the file  │
│ ├─────────────────────────────────────┤                            │
│ │                                     │                            │
│ │           .text                     │  Executable code           │
│ │     (your functions live here)      │  Read-only, executable     │
│ │                                     │                            │
│ ├─────────────────────────────────────┤                            │
│ │                                     │                            │
│ │           .rodata                   │  Read-only data            │
│ │     (string literals, constants)    │  Read-only, not executable │
│ │                                     │                            │
│ ├─────────────────────────────────────┤                            │
│ │                                     │                            │
│ │           .data                     │  Initialized variables     │
│ │     (var x: i32 = 42;)             │  Read-write                │
│ │                                     │                            │
│ ├─────────────────────────────────────┤                            │
│ │                                     │                            │
│ │           .bss                      │  Uninitialized variables   │
│ │     (var y: i32 = undefined;)      │  Read-write, zeroed        │
│ │                                     │                            │
│ └─────────────────────────────────────┘                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Special sections you might need:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ SPECIAL SECTIONS AND THEIR PURPOSES:                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ .init      Code that runs BEFORE main()                            │
│            Used for: C runtime setup, static constructors          │
│                                                                     │
│ .fini      Code that runs AFTER main() returns                     │
│            Used for: Cleanup, static destructors                    │
│                                                                     │
│ .vectors   Interrupt vector table (embedded)                       │
│            Must be at specific address (often 0x0000)              │
│                                                                     │
│ .ramfunc   Code that runs from RAM instead of flash (embedded)     │
│            Used for: Flash programming (can't run from flash       │
│            while erasing it!)                                       │
│                                                                     │
│ .bootloader  Bootloader code, often at fixed address               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Real examples:**

```zig
// 1. STARTUP CODE - Must run before anything else
fn initializeHardware() linksection(".init") void {
    // Set up clocks, memory controllers, etc.
    // This runs automatically before main()
}

// 2. INTERRUPT VECTOR TABLE - Must be at address 0x0000 on ARM Cortex-M
const vector_table linksection(".vectors") = [_]?*const fn () void{
    resetHandler,      // 0x00: Reset
    nmiHandler,        // 0x04: NMI
    hardFaultHandler,  // 0x08: Hard Fault
    // ... etc
};

// 3. CODE THAT RUNS FROM RAM - For flash programming
fn eraseFlashPage(page: u32) linksection(".ramfunc") void {
    // This function is copied to RAM at startup
    // It can run while we're erasing flash
    // (Can't execute code from flash while erasing it!)
}

// 4. DATA AT SPECIFIC ADDRESS - For bootloader handoff
var sharedData: u32 linksection(".shared_ram") = 0;
// Bootloader and app both know this address
// Used to pass data between them
```

**Linker script connection:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ HOW IT WORKS TOGETHER:                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Your Zig code:                                                      │
│ ┌───────────────────────────────────────────────────────────────┐  │
│ │ fn startup() linksection(".init") void { ... }                │  │
│ └───────────────────────────────────────────────────────────────┘  │
│                          │                                          │
│                          ▼                                          │
│ Linker script (link.ld):                                           │
│ ┌───────────────────────────────────────────────────────────────┐  │
│ │ SECTIONS {                                                     │  │
│ │     .init 0x08000000 : {   /* Flash start on STM32 */         │  │
│ │         *(.init)            /* Put all .init stuff here */    │  │
│ │     }                                                          │  │
│ │     .text : {                                                  │  │
│ │         *(.text)            /* Regular code after init */     │  │
│ │     }                                                          │  │
│ │ }                                                              │  │
│ └───────────────────────────────────────────────────────────────┘  │
│                          │                                          │
│                          ▼                                          │
│ Final binary:                                                       │
│ ┌───────────────────────────────────────────────────────────────┐  │
│ │ Address 0x08000000:  startup() code                           │  │
│ │ Address 0x08000100:  main() and other functions               │  │
│ └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

##### Summary: When You'll Use Each

```
┌─────────────────────────────────────────────────────────────────────┐
│                    WHEN TO USE EACH ATTRIBUTE                        │
├──────────────┬──────────────────────────────────────────────────────┤
│              │                                                      │
│   align()    │ • SIMD code (SSE, AVX, NEON)                        │
│              │ • Cache optimization (hot loops)                    │
│              │ • Memory-mapped I/O with alignment requirements     │
│              │ • DMA buffers                                        │
│              │                                                      │
├──────────────┼──────────────────────────────────────────────────────┤
│              │                                                      │
│  callconv()  │ • Calling C libraries (use .c)                      │
│              │ • Being called FROM C (use .c + export)             │
│              │ • Interrupt handlers (use .interrupt)               │
│              │ • Bootloaders/kernels (use .naked)                  │
│              │ • System calls (use .system)                        │
│              │                                                      │
├──────────────┼──────────────────────────────────────────────────────┤
│              │                                                      │
│ addrspace()  │ • GPU programming (CUDA, OpenCL, Vulkan compute)    │
│              │ • Embedded with multiple memory regions              │
│              │ • Memory-mapped I/O registers                        │
│              │ • Harvard architecture (separate code/data memory)  │
│              │                                                      │
├──────────────┼──────────────────────────────────────────────────────┤
│              │                                                      │
│ linksection()│ • Embedded startup code                             │
│              │ • Interrupt vector tables                            │
│              │ • Bootloaders                                        │
│              │ • Self-modifying code (must be in RAM)               │
│              │ • Shared memory between processes                    │
│              │                                                      │
└──────────────┴──────────────────────────────────────────────────────┘
```

---

Now let's see the simple version again:

```zig
// Simple function (most common) - NO optional expressions
fn add(a: u32, b: u32) u32 {
    return a + b;
}

// Function with ALIGNMENT
fn aligned() align(16) void {}

// Function with CALLING CONVENTION
fn cFunc() callconv(.c) void {}

// Function with ADDRESS SPACE (rare, usually on pointers not functions)
fn gpuFunc() addrspace(.global) void {}

// Function with LINKER SECTION
fn initFunc() linksection(".init") void {}

// Function with MULTIPLE attributes (very rare!)
fn complex() align(16) callconv(.c) linksection(".special") void {}
```

**Statistics from real codebases:**
```
┌────────────────────────────────────────────────────────────────┐
│ Analysis of ~10,000 functions in typical Zig projects:         │
├────────────────────────────────────────────────────────────────┤
│ No optional expressions:     ~95%   (simple functions)         │
│ Has callconv only:           ~3%    (C interop code)           │
│ Has align only:              ~1%    (SIMD, memory-mapped I/O)  │
│ Has linksection only:        ~0.5%  (embedded, bootloaders)    │
│ Has multiple attributes:     ~0.5%  (very specialized code)    │
└────────────────────────────────────────────────────────────────┘
```

This is why optimizing for the common case matters so much!

#### The Problem: Variable-Size Data

A function prototype can have:
- 0 parameters, 1 parameter, or many parameters
- Optional alignment expression
- Optional calling convention
- Optional address space
- Optional linker section

Storing ALL of these for EVERY function would waste memory. Most functions are simple!

**The Solution: Multiple Node Variants**

```
┌────────────────────────────────────────────────────────────────────┐
│                    FUNCTION PROTOTYPE VARIANTS                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  fn_proto_simple    (most common - ~80% of functions)              │
│  ─────────────────────────────────────────────────                 │
│  • 0 or 1 parameters                                               │
│  • No alignment, callconv, addrspace, section                      │
│  • Everything fits in the 8-byte Data field!                       │
│  • NO extra_data allocation needed                                 │
│                                                                     │
│  fn_proto_multi     (common - ~15% of functions)                   │
│  ─────────────────────────────────────────────────                 │
│  • 2+ parameters                                                   │
│  • No alignment, callconv, addrspace, section                      │
│  • Params stored in extra_data, but nothing else                   │
│                                                                     │
│  fn_proto_one       (rare - ~4% of functions)                      │
│  ─────────────────────────────────────────────────                 │
│  • 0 or 1 parameters                                               │
│  • HAS alignment/callconv/addrspace/section                        │
│  • Uses extra_data for the optional expressions                    │
│                                                                     │
│  fn_proto           (very rare - ~1% of functions)                 │
│  ─────────────────────────────────────────────────                 │
│  • 2+ parameters AND optional expressions                          │
│  • Full extra_data usage                                           │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

**The Decision Tree:**

```
                        Does it have align/callconv/
                        addrspace/section expressions?
                                   │
                    ┌──────────────┴──────────────┐
                    │ NO                          │ YES
                    ▼                             ▼
            How many params?              How many params?
                    │                             │
           ┌───────┴───────┐             ┌───────┴───────┐
           │ 0-1           │ 2+          │ 0-1           │ 2+
           ▼               ▼             ▼               ▼
    fn_proto_simple   fn_proto_multi  fn_proto_one   fn_proto
    (MOST COMPACT)                    (uses extra)  (MOST COMPLEX)
```

**Code That Makes The Decision:**

```zig
// Choose node variant based on complexity
if (align_expr == null and section_expr == null and
    callconv_expr == null and addrspace_expr == null) {
    // Simple case: no extra expressions needed
    switch (params) {
        .zero_or_one => |param| return p.setNode(fn_proto_index, .{
            .tag = .fn_proto_simple,
            .data = .{ .opt_node_and_opt_node = .{ param, return_type } },
            // Everything fits in 8 bytes! No extra_data needed.
        }),
        .multi => |span| return p.setNode(fn_proto_index, .{
            .tag = .fn_proto_multi,  // ← Our example uses this (2 params)
            .data = .{ .extra_range = span },
            // Only params go to extra_data
        }),
    }
} else {
    // Complex case: need to store optional expressions
    switch (params) {
        .zero_or_one => |param| {
            // fn_proto_one: store extras in extra_data
            const extra = try p.addExtra(FnProtoOne{
                .return_type = return_type,
                .align_expr = align_expr,
                .addrspace_expr = addrspace_expr,
                .section_expr = section_expr,
                .callconv_expr = callconv_expr,
            });
            return p.setNode(fn_proto_index, .{
                .tag = .fn_proto_one,
                .data = .{ .node_and_extra = .{ param, extra } },
            });
        },
        .multi => |span| {
            // fn_proto: full complexity, everything in extra_data
            // ... similar but with param range
        },
    }
}
```

**Memory Impact Example:**

```
Function: fn add(a: u32, b: u32) u32 { ... }

With fn_proto_multi (what we use):
┌─────────────────────────────────────────────────────────────────┐
│ Node (13 bytes):                                                │
│   tag: .fn_proto_multi                                          │
│   main_token: 1 ("fn")                                          │
│   data: { start: 0, end: 2 }  // range into extra_data          │
├─────────────────────────────────────────────────────────────────┤
│ extra_data (8 bytes):                                           │
│   [0]: param_node_a                                             │
│   [1]: param_node_b                                             │
├─────────────────────────────────────────────────────────────────┤
│ TOTAL: 21 bytes                                                 │
└─────────────────────────────────────────────────────────────────┘

If we used fn_proto (full variant) for EVERYTHING:
┌─────────────────────────────────────────────────────────────────┐
│ Node (13 bytes):                                                │
│   tag: .fn_proto                                                │
│   main_token: 1                                                 │
│   data: { extra_index }                                         │
├─────────────────────────────────────────────────────────────────┤
│ extra_data (24 bytes):                                          │
│   [0]: params_start                                             │
│   [1]: params_end                                               │
│   [2]: align_expr (null)      ← wasted!                         │
│   [3]: addrspace_expr (null)  ← wasted!                         │
│   [4]: section_expr (null)    ← wasted!                         │
│   [5]: callconv_expr (null)   ← wasted!                         │
├─────────────────────────────────────────────────────────────────┤
│ TOTAL: 37 bytes (76% more memory!)                              │
└─────────────────────────────────────────────────────────────────┘
```

**Why This Matters At Scale:**

```
Parsing Zig's standard library (~500,000 lines):
┌──────────────────────────────────────────────────────────────────┐
│ Estimated function count: ~15,000 functions                      │
│                                                                  │
│ With smart variants:                                             │
│   ~12,000 × fn_proto_simple (21 bytes)  = 252,000 bytes          │
│   ~2,500  × fn_proto_multi  (25 bytes)  =  62,500 bytes          │
│   ~500    × fn_proto_one/full (37 bytes)=  18,500 bytes          │
│   TOTAL: ~333 KB                                                 │
│                                                                  │
│ If everything used fn_proto:                                     │
│   ~15,000 × 37 bytes = 555 KB                                    │
│                                                                  │
│ SAVINGS: 222 KB (40% reduction!) just for function nodes         │
└──────────────────────────────────────────────────────────────────┘
```

This pattern repeats across the AST: blocks, calls, if statements, loops - all have optimized variants for common cases.

#### Step-by-Step: How The Parser Collects Data

Let's trace exactly what happens when parsing `fn add(a: u32, b: u32) u32`:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 1: Parse and Collect                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Parser state as we go:                                               │
│                                                                      │
│ Tokens: [fn] [add] [(] [a] [:] [u32] [,] [b] [:] [u32] [)] [u32] ... │
│          ↑                                                           │
│ 1. See "fn" → start parsing function prototype                      │
│    align_expr = null                                                 │
│    callconv_expr = null                                              │
│    addrspace_expr = null                                             │
│    section_expr = null                                               │
│                                                                      │
│ Tokens: [fn] [add] [(] [a] [:] [u32] [,] [b] [:] [u32] [)] [u32] ... │
│               ↑                                                      │
│ 2. Consume "add" → function name (main_token = 1)                   │
│                                                                      │
│ Tokens: [fn] [add] [(] [a] [:] [u32] [,] [b] [:] [u32] [)] [u32] ... │
│                    ↑                                                 │
│ 3. See "(" → start parameter list                                   │
│    scratch buffer: []  (empty)                                       │
│                                                                      │
│ 4. Parse first parameter "a: u32"                                   │
│    Create param node, add index to scratch buffer                   │
│    scratch buffer: [node_3]                                          │
│                                                                      │
│ 5. See "," → more parameters coming                                 │
│                                                                      │
│ 6. Parse second parameter "b: u32"                                  │
│    Create param node, add index to scratch buffer                   │
│    scratch buffer: [node_3, node_4]                                  │
│                                                                      │
│ 7. See ")" → end of parameters                                      │
│    param_count = 2                                                   │
│                                                                      │
│ Tokens: [fn] [add] [(] [a] [:] [u32] [,] [b] [:] [u32] [)] [u32] ... │
│                                                                ↑     │
│ 8. Parse return type "u32"                                          │
│    return_type = node_5 (identifier "u32")                          │
│                                                                      │
│ 9. Check for optional attributes:                                   │
│    See "align"? NO                                                  │
│    See "callconv"? NO                                               │
│    See "addrspace"? NO                                              │
│    See "linksection"? NO                                            │
│    All optional expressions remain null!                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 2: Make The Decision                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Current state:                                                       │
│   align_expr = null                                                  │
│   callconv_expr = null                                               │
│   addrspace_expr = null                                              │
│   section_expr = null                                                │
│   param_count = 2                                                    │
│   scratch buffer = [node_3, node_4]                                  │
│                                                                      │
│ Decision process:                                                    │
│                                                                      │
│   if (align_expr == null AND                                        │
│       callconv_expr == null AND                                     │
│       addrspace_expr == null AND                                    │
│       section_expr == null) {                                       │
│       // YES! All are null ✓                                        │
│                                                                      │
│       if (param_count <= 1) {                                       │
│           // NO, we have 2 params                                   │
│           use fn_proto_simple                                        │
│       } else {                                                       │
│           // YES! 2+ params ✓                                       │
│           use fn_proto_multi  ← THIS ONE!                           │
│       }                                                              │
│   }                                                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 3: Create The Node                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. Copy params from scratch buffer to extra_data:                   │
│                                                                      │
│    extra_data before: [...]                                          │
│    extra_data after:  [..., node_3, node_4]                          │
│                             ↑       ↑                                │
│                           idx 10  idx 11                             │
│                                                                      │
│ 2. Create the fn_proto_multi node:                                  │
│                                                                      │
│    ┌────────────────────────────────────────────────────────────┐   │
│    │ Node {                                                      │   │
│    │   tag: .fn_proto_multi,                                    │   │
│    │   main_token: 1,  // points to "add" token                 │   │
│    │   data: .extra_range = {                                   │   │
│    │       start: 10,  // first param at extra_data[10]         │   │
│    │       end: 12,    // exclusive, so params are [10, 11]     │   │
│    │   }                                                         │   │
│    │ }                                                           │   │
│    └────────────────────────────────────────────────────────────┘   │
│                                                                      │
│ 3. Return type is stored separately (in the node's extra data)     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### The Scratch Buffer Explained

The parser uses a temporary "scratch buffer" to collect items before knowing how many there will be:

```zig
pub const Parse = struct {
    // ... other fields ...
    scratch: std.ArrayList(Node.Index),  // Temporary workspace
};
```

**Why a scratch buffer?**

```
Problem: We don't know how many parameters until we see ")"

  fn foo( ??? ) ...
          ↑
          Could be 0, 1, 2, 10, 100 parameters!

Solution: Collect into scratch buffer, then copy to extra_data

  1. Parse each param → append to scratch
  2. See ")" → we now know the count!
  3. Copy scratch[start..end] to extra_data
  4. Store the range in the node
  5. Clear scratch (ready for next use)
```

```
┌────────────────────────────────────────────────────────────────────┐
│                    SCRATCH BUFFER LIFECYCLE                         │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Start parsing fn add(a: u32, b: u32):                             │
│                                                                     │
│  scratch: [ ]                          // empty                    │
│           ↑ scratch_top = 0                                        │
│                                                                     │
│  After parsing param "a":                                          │
│                                                                     │
│  scratch: [ node_3 ]                                               │
│                    ↑ scratch_top = 1                               │
│                                                                     │
│  After parsing param "b":                                          │
│                                                                     │
│  scratch: [ node_3, node_4 ]                                       │
│                           ↑ scratch_top = 2                        │
│                                                                     │
│  See ")" - done with params:                                       │
│                                                                     │
│  extra_data: [..., node_3, node_4 ]                                │
│                    ↑              ↑                                │
│               start=10        end=12                                │
│                                                                     │
│  scratch: [ node_3, node_4 ]   // still has data, but...          │
│           ↑ scratch_top = 0     // reset for next use!             │
│                                                                     │
│  The scratch buffer is reused for the next list we need to parse!  │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

#### Why Not Just Use `ArrayList` Directly?

You might wonder: why have both scratch buffer AND extra_data?

```
┌────────────────────────────────────────────────────────────────────┐
│ Option A: Store param list directly in ArrayList (BAD)             │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Node {                                                              │
│   tag: .fn_proto,                                                  │
│   params: ArrayList(Node.Index),  // POINTER to heap allocation!   │
│ }                                                                   │
│                                                                     │
│ Problems:                                                           │
│ - Each ArrayList has overhead (pointer + length + capacity)        │
│ - Thousands of tiny heap allocations                               │
│ - Poor cache locality (params scattered in memory)                 │
│ - Node size becomes variable                                       │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ Option B: Use shared extra_data array (GOOD - what Zig does)       │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Node {                                                              │
│   tag: .fn_proto_multi,                                            │
│   data: { start: 10, end: 12 },  // Just two integers!             │
│ }                                                                   │
│                                                                     │
│ Benefits:                                                           │
│ - Fixed-size nodes (always 13 bytes)                               │
│ - Single contiguous extra_data array                               │
│ - Great cache locality                                             │
│ - One large allocation instead of many small ones                  │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

#### Complete Node Selection Table

Here's every function prototype variant with examples:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ VARIANT           │ PARAMS │ EXTRAS │ EXAMPLE                          │
├───────────────────┼────────┼────────┼──────────────────────────────────┤
│                   │        │        │                                  │
│ fn_proto_simple   │  0     │  none  │ fn foo() void {}                 │
│                   │        │        │                                  │
│ fn_proto_simple   │  1     │  none  │ fn bar(x: u32) u32 {}            │
│                   │        │        │                                  │
│ fn_proto_multi    │  2+    │  none  │ fn add(a: u32, b: u32) u32 {}    │
│                   │        │        │                                  │
│ fn_proto_one      │  0     │  some  │ fn init() callconv(.c) void {}   │
│                   │        │        │                                  │
│ fn_proto_one      │  1     │  some  │ fn isr(ctx: *Ctx)                │
│                   │        │        │     callconv(.interrupt) void {} │
│                   │        │        │                                  │
│ fn_proto          │  2+    │  some  │ fn simd(a: @Vector, b: @Vector)  │
│                   │        │        │     align(32) @Vector {}         │
│                   │        │        │                                  │
└─────────────────────────────────────────────────────────────────────────┘

Data storage for each:

fn_proto_simple:   data = { param_or_null, return_type }     // All in 8 bytes!
fn_proto_multi:    data = { params_start, params_end }       // Points to extra_data
fn_proto_one:      data = { param_or_null, extra_index }     // Extras in extra_data
fn_proto:          data = { extra_index }                    // Everything in extra_data
```

### Step 6: Parse Block Body

```
parseBlock() called

Tokens: [{] [return] [a] [+] [b] [;] [}]
         ↑

See "{"? Yes!

Parse statements:
  - parseStatement() finds "return"
  - parseReturnExpr() parses "a + b"
    - This uses precedence climbing!
  - Expect ";" → found

See "}"? Yes → block complete

Only 1 statement → use block_two variant (optimized!)
```

### Final AST Structure

```
                    root (node 0)
                      │
                   fn_decl (node 1)
                   /      \
        fn_proto_multi    block_two
            (node 2)       (node 8)
           /   |   \           │
      param  param  u32     return
      (3)    (4)    (5)      (9)
      / \    / \               │
     a  u32 b  u32           add
        (6)    (7)           (10)
                            /    \
                       ident    ident
                        (11)     (12)
                         "a"      "b"
```

---

## Extra Data Storage

When node data exceeds 8 bytes, it goes to `extra_data`:

```zig
pub const SubRange = struct {
    start: ExtraIndex,
    end: ExtraIndex,
};

fn addExtra(p: *Parse, extra: anytype) Allocator.Error!ExtraIndex {
    const fields = std.meta.fields(@TypeOf(extra));
    try p.extra_data.ensureUnusedCapacity(p.gpa, fields.len);

    const result: ExtraIndex = @enumFromInt(p.extra_data.items.len);

    inline for (fields) |field| {
        const data: u32 = switch (field.type) {
            Node.Index, Node.OptionalIndex, OptionalTokenIndex, ExtraIndex
                => @intFromEnum(@field(extra, field.name)),
            TokenIndex
                => @field(extra, field.name),
            else => @compileError("unexpected field type"),
        };
        p.extra_data.appendAssumeCapacity(data);
    }

    return result;
}
```

### Visualizing Extra Data

```
Scenario: A block with 5 statements

Node can only store 8 bytes (2 indices).
How do we store 5 statement indices?

Solution: Store a RANGE pointing to extra_data

┌─────────────────────────────────────────────────────────────┐
│  nodes array:                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ...  │ block_node                              │ ... │   │
│  │      │ tag: .block                             │     │   │
│  │      │ data: { start: 10, end: 15 }  ─────────┼──┐  │   │
│  └──────┴────────────────────────────────────────┴──┼──┘   │
│                                                     │      │
└─────────────────────────────────────────────────────┼──────┘
                                                      │
┌─────────────────────────────────────────────────────┼──────┐
│  extra_data array:                                  ▼      │
│  ┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐ │
│  │ ...│ ...│ ...│ ...│stmt│stmt│stmt│stmt│stmt│ ...│ ...│ │
│  │    │    │    │    │ 0  │ 1  │ 2  │ 3  │ 4  │    │    │ │
│  └────┴────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘ │
│                        ↑                       ↑           │
│                      index 10               index 15       │
│                       start                   end          │
└────────────────────────────────────────────────────────────┘
```

### Extra Data Structures

```zig
pub const GlobalVarDecl = struct {
    type_node: OptionalIndex,
    align_node: OptionalIndex,
    addrspace_node: OptionalIndex,
    section_node: OptionalIndex,
};

pub const FnProto = struct {
    params_start: ExtraIndex,
    params_end: ExtraIndex,
    align_expr: OptionalIndex,
    addrspace_expr: OptionalIndex,
    section_expr: OptionalIndex,
    callconv_expr: OptionalIndex,
};

pub const If = struct {
    then_expr: Index,
    else_expr: Index,
};
```

---

## Error Recovery: Don't Stop at First Error

The parser can recover from errors and report multiple issues:

```zig
fn expectStatementRecoverable(p: *Parse) Error!?Node.Index {
    while (true) {
        return p.expectStatement(true) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseError => {
                p.findNextStmt();  // Skip to next statement
                switch (p.tokenTag(p.tok_i)) {
                    .r_brace => return null,
                    .eof => return error.ParseError,
                    else => continue,
                }
            },
        };
    }
}

fn findNextStmt(p: *Parse) void {
    var level: u32 = 0;
    while (true) {
        const tok = p.nextToken();
        switch (p.tokenTag(tok)) {
            .l_brace => level += 1,
            .r_brace => {
                if (level == 0) {
                    p.tok_i -= 1;
                    return;
                }
                level -= 1;
            },
            .semicolon => {
                if (level == 0) return;
            },
            .eof => {
                p.tok_i -= 1;
                return;
            },
            else => {},
        }
    }
}
```

### Visualizing Error Recovery

```
Source with errors:
┌─────────────────────────────────────────────────────────────┐
│ fn broken() {                                               │
│     const x =      // ERROR: missing expression             │
│     const y = 5;   // This should still parse!              │
│     return y;                                               │
│ }                                                           │
└─────────────────────────────────────────────────────────────┘

Without recovery:
  Parser stops at first error. Only reports "missing expression".

With recovery:
┌─────────────────────────────────────────────────────────────┐
│ 1. Try to parse "const x ="                                 │
│ 2. ERROR: missing expression after "="                      │
│ 3. Call findNextStmt() - skip until ";"                     │
│ 4. Continue parsing from "const y = 5;"                     │
│ 5. Successfully parse "const y = 5;"                        │
│ 6. Successfully parse "return y;"                           │
│                                                             │
│ Reports error but also builds partial AST!                  │
└─────────────────────────────────────────────────────────────┘

The `findNextStmt` algorithm:

Tokens: const x = [???] const y = 5 ; return y ; }
                   ↑
                   Error here!

Step 1: level=0, look for ";" or matching "}"
Step 2: Skip unknown tokens...
Step 3: Found ";" at level=0 → stop here!

Tokens: const x = [???] const y = 5 ; return y ; }
                                    ↑
                                    Resume here
```

---

## Token Consumption Patterns

The parser uses helper functions to consume tokens:

```zig
// Try to eat a token (returns null if not matched)
fn eatToken(p: *Parse, tag: Token.Tag) ?TokenIndex {
    return if (p.tokenTag(p.tok_i) == tag) p.nextToken() else null;
}

// Expect a token (reports error if not matched)
fn expectToken(p: *Parse, tag: Token.Tag) Error!TokenIndex {
    if (p.tokenTag(p.tok_i) != tag) {
        return p.failMsg(.{
            .tag = .expected_token,
            .token = p.tok_i,
            .extra = .{ .expected_tag = tag },
        });
    }
    return p.nextToken();
}

fn nextToken(p: *Parse) TokenIndex {
    const result = p.tok_i;
    p.tok_i += 1;
    return result;
}
```

### Visual: eat vs expect

```
Scenario: Parsing optional trailing comma

fn parseList(p: *Parse) !void {
    // ... parse items ...

    // Trailing comma is optional
    _ = p.eatToken(.comma);  // If not there, no error!

    // Closing bracket is required
    _ = try p.expectToken(.r_bracket);  // Error if missing!
}

┌──────────────────────────────────────────────────────────┐
│ eatToken(.comma)                                         │
│                                                          │
│ Input: [1, 2, 3]   →  comma not there, returns null     │
│                 ↑      (no error, continue parsing)      │
│                                                          │
│ Input: [1, 2, 3,]  →  comma found! returns token index  │
│                 ↑      (consumed and continue)           │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│ expectToken(.r_bracket)                                  │
│                                                          │
│ Input: [1, 2, 3]   →  "]" found! returns token index    │
│                 ↑                                        │
│                                                          │
│ Input: [1, 2, 3    →  ERROR: expected "]"               │
│                 ↑      (reports error, may recover)      │
└──────────────────────────────────────────────────────────┘
```

---

## Memory Efficiency: The Numbers

```zig
// From Ast.parse():

// Empirically, Zig source has 8:1 ratio of bytes to tokens
const estimated_token_count = source.len / 8;
try tokens.ensureTotalCapacity(gpa, estimated_token_count);

// Empirically, Zig source has 2:1 ratio of tokens to nodes
const estimated_node_count = (tokens.len + 2) / 2;
try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);
```

### Real-World Example

```
Parsing a 10,000 byte source file:

┌─────────────────────────────────────────────────────────────┐
│ Source Size:     10,000 bytes                               │
├─────────────────────────────────────────────────────────────┤
│ Estimated Tokens: 10,000 / 8 = 1,250 tokens                 │
│ Token Size:       8 bytes each (start, end)                 │
│ Token Memory:     1,250 × 8 = 10,000 bytes                  │
├─────────────────────────────────────────────────────────────┤
│ Estimated Nodes:  1,250 / 2 = 625 nodes                     │
│ Node Size:        13 bytes each                             │
│ Node Memory:      625 × 13 = 8,125 bytes                    │
├─────────────────────────────────────────────────────────────┤
│ Extra Data:       ~2,000 bytes (estimate)                   │
├─────────────────────────────────────────────────────────────┤
│ TOTAL AST:        ~20,000 bytes                             │
│                   = 2× source size                          │
│                                                             │
│ Compare to typical AST implementations:                     │
│   - With per-node allocations: ~100,000+ bytes              │
│   - With pointer-heavy trees: ~50,000+ bytes                │
│                                                             │
│ Zig's AST is 2.5-5× more memory efficient!                  │
└─────────────────────────────────────────────────────────────┘
```

### Why It's Efficient

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Compact nodes (13 bytes)                                 │
│    - Tag: 1 byte (not 8 for enum pointer)                   │
│    - Indices: 4 bytes (not 8-byte pointers)                 │
│    - Data union: reuses space for different node types      │
├─────────────────────────────────────────────────────────────┤
│ 2. Zero-copy source                                         │
│    - Tokens reference original source bytes                 │
│    - No string duplication                                  │
├─────────────────────────────────────────────────────────────┤
│ 3. Specialized variants                                     │
│    - block_two vs block saves extra_data allocations        │
│    - call_one vs call for common 0-1 arg calls              │
├─────────────────────────────────────────────────────────────┤
│ 4. Flat storage                                             │
│    - All nodes in one contiguous array                      │
│    - No per-node allocation overhead (16+ bytes each)       │
│    - Better cache locality                                  │
├─────────────────────────────────────────────────────────────┤
│ 5. Index-based references                                   │
│    - 4-byte indices vs 8-byte pointers                      │
│    - Halves the cost of every reference!                    │
└─────────────────────────────────────────────────────────────┘
```

---

## High-Level AST Accessors

The AST provides convenient accessors to hide the complexity:

```zig
pub const full = struct {
    pub const VarDecl = struct {
        visib_token: ?TokenIndex,
        extern_export_token: ?TokenIndex,
        lib_name: ?TokenIndex,
        threadlocal_token: ?TokenIndex,
        comptime_token: ?TokenIndex,
        ast: Components,

        pub const Components = struct {
            mut_token: TokenIndex,
            type_node: Node.OptionalIndex,
            align_node: Node.OptionalIndex,
            addrspace_node: Node.OptionalIndex,
            section_node: Node.OptionalIndex,
            init_node: Node.OptionalIndex,
        };
    };

    // Similar for FnProto, If, While, For, etc.
};

pub fn fullVarDecl(tree: Ast, node: Node.Index) ?full.VarDecl {
    return switch (tree.nodeTag(node)) {
        .global_var_decl => tree.globalVarDecl(node),
        .local_var_decl => tree.localVarDecl(node),
        .aligned_var_decl => tree.alignedVarDecl(node),
        .simple_var_decl => tree.simpleVarDecl(node),
        else => null,
    };
}
```

### Why Accessors?

```
Problem: Multiple node variants for the same concept

  .global_var_decl  - uses extra_data
  .local_var_decl   - different layout
  .simple_var_decl  - optimized, no extra_data
  .aligned_var_decl - has alignment

Raw access is error-prone:
  // Wrong! Different nodes have different layouts
  const type_node = ast.nodes.items(.data)[node].something???

Solution: fullVarDecl() returns a unified view

  if (ast.fullVarDecl(node)) |var_decl| {
      // Works for ALL var decl variants!
      if (var_decl.ast.type_node) |type_node| {
          // Process type
      }
  }
```

---

## Complete Example: From Source to Tree

### Source Code

```zig
pub fn max(a: u32, b: u32) u32 {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}
```

### Token Stream

```
[pub] [fn] [max] [(] [a] [:] [u32] [,] [b] [:] [u32] [)] [u32] [{]
  0     1    2    3   4   5    6    7   8   9   10   11   12   13

[if] [(] [a] [>] [b] [)] [{] [return] [a] [;] [}] [else] [{] [return] [b] [;] [}] [}]
 14   15  16  17  18  19  20    21    22  23  24   25    26    27     28  29  30  31
```

### Resulting AST

```
                              root (0)
                                │
                            fn_decl (1)
                           /        \
                   fn_proto_multi    block_two (9)
                       (2)              │
                    /  |  \            if (10)
                 param param u32     /   |   \
                  (3)   (4)  (5)  cond  then  else
                 / \    / \       (11)  (12)  (13)
                a u32  b u32       │      │     │
                  (6)    (7)    greater block block
                                  / \     │     │
                                 a   b  return return
                                          │     │
                                          a     b

Node Table:
┌──────┬─────────────────┬───────────┬─────────────────────────┐
│ Idx  │ Tag             │ MainToken │ Data                    │
├──────┼─────────────────┼───────────┼─────────────────────────┤
│  0   │ root            │     0     │ extra_range: 0..1       │
│  1   │ fn_decl         │     1     │ {proto: 2, body: 9}     │
│  2   │ fn_proto_multi  │     1     │ {params: extra, ret: 5} │
│  3   │ param           │     4     │ {name: _, type: 6}      │
│  4   │ param           │     8     │ {name: _, type: 7}      │
│  5   │ identifier      │    12     │ (u32)                   │
│  6   │ identifier      │     6     │ (u32)                   │
│  7   │ identifier      │    10     │ (u32)                   │
│  8   │ (reserved)      │     -     │ -                       │
│  9   │ block_two       │    13     │ {stmt: 10, _}           │
│ 10   │ if              │    14     │ {cond: 11, extra: ...}  │
│ 11   │ greater_than    │    17     │ {lhs: a, rhs: b}        │
│ ...  │ ...             │    ...    │ ...                     │
└──────┴─────────────────┴───────────┴─────────────────────────┘
```

---

## Summary: The Parser's Job

```
┌─────────────────────────────────────────────────────────────┐
│                      PARSER OVERVIEW                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  INPUT:                                                      │
│    Flat token stream from tokenizer                          │
│    [fn] [add] [(] [a] [:] [u32] [)] [u32] [{] [return] ...   │
│                                                              │
│  PROCESS:                                                    │
│    1. Recursive descent through grammar rules                │
│    2. Precedence climbing for expressions                    │
│    3. Build tree structure showing relationships             │
│    4. Recover from errors to report multiple issues          │
│                                                              │
│  OUTPUT:                                                     │
│    Compact AST in flat arrays                                │
│                                                              │
│            fn_decl                                           │
│           /       \                                          │
│      fn_proto    block                                       │
│        / \          \                                        │
│     param param   return                                     │
│                      |                                       │
│                     add                                      │
│                    /   \                                     │
│                   a     b                                    │
│                                                              │
│  KEY TECHNIQUES:                                             │
│    • 13-byte nodes with union data                           │
│    • MultiArrayList (SoA) for cache efficiency               │
│    • Specialized variants (block_two, call_one)              │
│    • Extra data for overflow                                 │
│    • Index-based references (not pointers)                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Conclusion

Zig's parser and AST are designed for both correctness and efficiency:

- **Recursive descent** makes the parser readable and maintainable
- **Precedence climbing** handles expressions elegantly
- **MultiArrayList** provides cache-friendly storage
- **Node specialization** optimizes common cases
- **Error recovery** enables better diagnostics

The AST is the foundation for everything that follows. In the next article, we'll see how **AstGen** transforms this tree into **ZIR** (Zig Intermediate Representation).

---

**Previous**: [Part 2: Tokenizer](./02-tokenizer.md)
**Next**: [Part 4: ZIR Generation](./04-zir-generation.md)

**Series Index**:
1. [Bootstrap Process](./01-bootstrap-process.md)
2. [Tokenizer](./02-tokenizer.md)
3. **Parser and AST** (this article)
4. [ZIR Generation](./04-zir-generation.md)
5. [Semantic Analysis](./05-sema.md)
6. [AIR and Code Generation](./06-air-codegen.md)
7. [Linking](./07-linking.md)
