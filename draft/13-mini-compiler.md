---
title: "Building a Mini Zig Compiler: From Source to C"
date: 2025-12-17
---

# Building a Mini Zig Compiler: From Source to C
*Understanding the real Zig compiler architecture by building a subset compiler*

---

## Introduction

The Zig compiler is a marvel of engineering - it transforms Zig source code through multiple intermediate representations before producing efficient machine code. In this post, we'll build a **mini Zig compiler** that follows the same architecture:

**Source → Lexer → Parser → AST → ZIR → Sema → AIR → C Code**

Our compiler supports:
- Functions: `pub fn add(a: i32, b: i32) i32 { ... }`
- Declarations: `const x: i32 = 5;` and `var y: i32 = 10;`
- Arithmetic: `+`, `-`, `*`, `/`
- Types: `i32`, `i64`, `bool`, `void`
- Return statements

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    MINI ZIG COMPILER PIPELINE                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source: pub fn add(a: i32, b: i32) i32 { return a + b; }                  │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 1: LEXER (Tokenizer)         │                                   │
│   │  Breaks text into tokens            │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   Tokens: [pub, fn, identifier(add), lparen, ...]                           │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 2: PARSER                    │                                   │
│   │  Builds Abstract Syntax Tree        │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   AST:  FnDecl(add)                                                         │
│           └── Block                                                          │
│                 └── Return(Binary(+, a, b))                                  │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 3: ZIR GENERATION            │                                   │
│   │  Flat IR with unresolved names      │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   ZIR: %0 = decl_fn("add")                                                  │
│        %1 = param_ref(0)                                                     │
│        %2 = param_ref(1)                                                     │
│        %3 = add(%1, %2)                                                      │
│        %4 = ret(%3)                                                          │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 4: SEMA (Semantic Analysis)  │                                   │
│   │  Type checking, name resolution     │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   AIR: %0 = decl_fn("add"): i32                                             │
│        %1 = param(0): i32                                                    │
│        %2 = param(1): i32                                                    │
│        %3 = add(%1, %2): i64                                                │
│        %4 = ret(%3): i32                                                     │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 5: CODE GENERATION           │                                   │
│   │  Generate C code from AIR           │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   C Code:                                                                    │
│   int32_t add(int32_t p0, int32_t p1) {                                     │
│       int32_t t1 = p0;                                                       │
│       int32_t t2 = p1;                                                       │
│       int64_t t3 = t1 + t2;                                                  │
│       return t3;                                                             │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
mini-compiler/
├── build.zig             # Build configuration
└── src/
    ├── main.zig          # Entry point - ties everything together
    ├── token.zig         # Token type definitions
    ├── lexer.zig         # Stage 1: Tokenizer
    ├── ast.zig           # AST node definitions
    ├── parser.zig        # Stage 2: Parser (precedence climbing)
    ├── zir.zig           # Stage 3: ZIR (Zig IR) generation
    ├── sema.zig          # Stage 4: Semantic Analysis
    ├── air.zig           # AIR (Analyzed IR) definitions
    ├── codegen.zig       # Stage 5: C Code Generation
    └── llvm_codegen.zig  # Stage 5 (alt): LLVM IR Generation
```

Build and run:
```bash
zig build run                # Default: C backend
zig build run -- --backend=llvm  # LLVM backend
```

---

## Stage 1: The Lexer

The lexer breaks source text into tokens - the smallest meaningful units of Zig syntax.

### Token Types

```zig
pub const TokenType = enum {
    // Keywords
    keyword_fn,
    keyword_pub,
    keyword_const,
    keyword_var,
    keyword_return,
    keyword_true,
    keyword_false,

    // Types (only 4 primitive types)
    type_i32,
    type_i64,
    type_bool,
    type_void,

    // Literals (integers only)
    int_literal,

    // Identifiers
    identifier,

    // Operators (arithmetic + assignment)
    plus,       // +
    minus,      // -
    star,       // *
    slash,      // /
    equal,      // =

    // Delimiters
    lparen,     // (
    rparen,     // )
    lbrace,     // {
    rbrace,     // }
    comma,      // ,
    colon,      // :
    semicolon,  // ;

    // Special
    eof,
    invalid,
};
```

### Keyword Lookup

Zig's `comptime` makes keyword lookup elegant:

```zig
/// Keyword lookup table - built at compile time
pub const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "fn", .keyword_fn },
    .{ "pub", .keyword_pub },
    .{ "const", .keyword_const },
    .{ "var", .keyword_var },
    .{ "return", .keyword_return },
    .{ "true", .keyword_true },
    .{ "false", .keyword_false },
    // Type keywords
    .{ "i32", .type_i32 },
    .{ "i64", .type_i64 },
    .{ "bool", .type_bool },
    .{ "void", .type_void },
});

/// Look up keyword or return identifier
pub fn lookupIdentifier(lexeme: []const u8) TokenType {
    return keywords.get(lexeme) orelse .identifier;
}
```

### Lexer Implementation

```zig
pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    start_column: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .start_column = 1,
        };
    }

    fn peek(self: *Lexer) u8 {
        if (self.pos >= self.source.len) return 0;
        return self.source[self.pos];
    }

    fn advance(self: *Lexer) u8 {
        if (self.pos >= self.source.len) return 0;
        const c = self.source[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    fn makeToken(self: *Lexer, token_type: TokenType, len: usize) Token {
        const start = self.pos;
        for (0..len) |_| {
            _ = self.advance();
        }
        return .{
            .type = token_type,
            .lexeme = self.source[start..self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();
        self.start_column = self.column;

        if (self.pos >= self.source.len) {
            return .{ .type = .eof, .lexeme = "", .line = self.line, .column = self.column };
        }

        const c = self.peek();

        // Numbers
        if (isDigit(c)) return self.scanNumber();

        // Identifiers and keywords
        if (isAlpha(c)) return self.scanIdentifier();

        // Single-character tokens (no multi-char operators in simplified grammar)
        switch (c) {
            '+' => return self.makeToken(.plus, 1),
            '-' => return self.makeToken(.minus, 1),
            '*' => return self.makeToken(.star, 1),
            '/' => return self.makeToken(.slash, 1),
            '=' => return self.makeToken(.equal, 1),
            '(' => return self.makeToken(.lparen, 1),
            ')' => return self.makeToken(.rparen, 1),
            '{' => return self.makeToken(.lbrace, 1),
            '}' => return self.makeToken(.rbrace, 1),
            ',' => return self.makeToken(.comma, 1),
            ':' => return self.makeToken(.colon, 1),
            ';' => return self.makeToken(.semicolon, 1),
            else => return self.makeToken(.invalid, 1),
        }
    }

    fn scanIdentifier(self: *Lexer) Token {
        const start = self.pos;
        while (isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }
        const lexeme = self.source[start..self.pos];
        return .{
            .type = token.lookupIdentifier(lexeme),
            .lexeme = lexeme,
            .line = self.line,
            .column = self.start_column,
        };
    }
};
```

### Tokenization Example

```
Input: "pub fn add(a: i32, b: i32) i32 {"

Tokens:
┌────────────────┬─────────┬──────┐
│ Token Type     │ Lexeme  │ Line │
├────────────────┼─────────┼──────┤
│ keyword_pub    │ "pub"   │ 1    │
│ keyword_fn     │ "fn"    │ 1    │
│ identifier     │ "add"   │ 1    │
│ lparen         │ "("     │ 1    │
│ identifier     │ "a"     │ 1    │
│ colon          │ ":"     │ 1    │
│ type_i32       │ "i32"   │ 1    │
│ comma          │ ","     │ 1    │
│ identifier     │ "b"     │ 1    │
│ colon          │ ":"     │ 1    │
│ type_i32       │ "i32"   │ 1    │
│ rparen         │ ")"     │ 1    │
│ type_i32       │ "i32"   │ 1    │
│ lbrace         │ "{"     │ 1    │
└────────────────┴─────────┴──────┘
```

---

## Stage 2: The Parser

The parser transforms tokens into an Abstract Syntax Tree (AST).

### AST Node Types

```zig
pub const Node = union(enum) {
    // Declarations
    fn_decl: FnDecl,
    const_decl: ConstDecl,
    var_decl: VarDecl,

    // Statements
    block: Block,
    return_stmt: ReturnStmt,
    expr_stmt: ExprStmt,

    // Expressions
    int_literal: i64,
    bool_literal: bool,
    identifier: []const u8,
    binary: Binary,
    unary: Unary,
    call: Call,
    grouped: Grouped,

    // Top-level
    root: Root,
};

pub const FnDecl = struct {
    is_pub: bool,
    name: []const u8,
    params: []const Param,
    return_type: TypeExpr,
    body: *Node,  // block
};

pub const Binary = struct {
    op: BinaryOp,
    left: *Node,
    right: *Node,
};

/// Binary operators - arithmetic only (no comparisons in simplified grammar)
pub const BinaryOp = enum {
    add,  // +
    sub,  // -
    mul,  // *
    div,  // /
};

/// Unary operators
pub const UnaryOp = enum {
    neg,  // - (unary minus)
};
```

### Precedence Climbing Parser

The parser uses **precedence climbing** - a technique where each operator has a "binding power" that determines how tightly it grabs its operands.

#### Binding Power

Think of binding power as grip strength. When two operators compete for the same number, the one with stronger grip wins:

```
3 + 5 * 2
    │   │
    +   * ← both want the 5
```

`*` has binding power 20, `+` has 10. The `*` grips tighter, so it gets the 5.

| Operator | Binding Power | Meaning |
|----------|---------------|---------|
| `+` `-`  | 10            | Loose grip |
| `*` `/`  | 20            | Tight grip |

#### The Core Algorithm

```zig
//===========================================================================
// BINDING POWER
//===========================================================================
// How tightly does an operator hold onto its operands?
// Higher number = tighter grip = happens first
//
//   3 + 4 * 2
//       ↑   ↑
//       +   * ← both want the 4, but * grips tighter (20 > 10)
//
const POWER = struct {
    const NONE: i32 = 0;       // not an operator
    const ADD_SUB: i32 = 10;   // + -  (loose grip)
    const MUL_DIV: i32 = 20;   // * /  (tight grip)
};

fn bindingPower(token: TokenType) i32 {
    return switch (token) {
        .plus, .minus => POWER.ADD_SUB,
        .star, .slash => POWER.MUL_DIV,
        else => POWER.NONE,
    };
}

fn isOperator(token: TokenType) bool {
    return bindingPower(token) > POWER.NONE;
}

fn toOperator(token: TokenType) BinaryOp {
    return switch (token) {
        .plus => .add,
        .minus => .sub,
        .star => .mul,
        .slash => .div,
        else => unreachable,
    };
}

//===========================================================================
// EXPRESSION PARSER
//===========================================================================

/// Entry point: parse a full expression
fn parseExpression(self: *Parser) !*Node {
    return self.parseExprAbove(POWER.NONE);
}

/// Parse expression, but only grab operators STRONGER than `threshold`.
/// Weaker operators are left for the caller.
fn parseExprAbove(self: *Parser, threshold: i32) !*Node {
    // ----- Step 1: Get the left side -----
    var left = try self.parseAtom();

    // ----- Step 2: Extend with operators -----
    while (isOperator(self.current().type)) {
        const op_token = self.current();
        const op_power = bindingPower(op_token.type);

        // Is this operator stronger than our threshold?
        const dominated_by_caller = (op_power <= threshold);
        if (dominated_by_caller) {
            // No - this operator is too weak for us.
            // Leave it for whoever called us.
            break;
        }

        // Yes - this operator is ours. Consume it.
        _ = self.advance();

        // ----- Step 3: Get the right side -----
        // What belongs to the right side?
        // Everything that binds STRONGER than this operator.
        const right = try self.parseExprAbove(op_power);

        // ----- Step 4: Combine -----
        left = try self.createNode(.{
            .binary = .{
                .op = toOperator(op_token.type),
                .left = left,
                .right = right,
            },
        });
    }

    return left;
}
```

**The key insight:** When we see an operator, we ask two questions:
1. Is it strong enough for us? (`op_power > threshold`)
2. What belongs to its right side? (Everything with `power > op_power`)

#### Who is "the caller"?

Since `parseExprAbove` calls itself, there's a **chain of callers**:

```
parseExpression()
    │
    └─► parseExprAbove(threshold=0)      ← OUTER call
            │
            └─► parseExprAbove(threshold=10)   ← INNER call (caller = outer)
                    │
                    └─► parseExprAbove(threshold=20)  ← INNERMOST (caller = inner)
```

When the innermost call finishes, it **returns** to its caller (the inner call).
When the inner call finishes, it **returns** to its caller (the outer call).

**"Leave it for the caller"** means: "I won't handle this operator. I'll return what I have, and whoever called me will see this operator next."

**Example:** Parsing `8 - 3 - 2`

```
OUTER: parseExprAbove(threshold=0)
│
├─ Get 8
├─ See '-' (power=10). Is 10 > 0? YES → I'll take it
├─ Call INNER to get right side...
│
│   INNER: parseExprAbove(threshold=10)
│   │
│   ├─ Get 3
│   ├─ See '-' (power=10). Is 10 > 10? NO → not mine!
│   └─ Return 3  ← leaves the '-' unconsumed
│
├─ Build: Sub(8, 3)
├─ See '-' (power=10). Is 10 > 0? YES → I'll take this one too!
├─ Call another INNER to get right side...
│   └─ Returns 2
├─ Build: Sub(Sub(8,3), 2)
└─ Done!
```

The second `-` was "left for the caller" (OUTER) because INNER's threshold was 10, and `-` has power 10, which is NOT greater than 10.

#### Walkthrough: Parsing `3 + 5 * 2`

```
parseExprAbove(threshold=0):  "Grab operators stronger than 0 (all of them)"
│
├─ parseAtom() → Int(3)
│
├─ See '+' (power=10)
│   ├─ Is 10 > 0?  YES → this operator is ours
│   ├─ Consume the '+'
│   ├─ parseExprAbove(threshold=10):  "Grab operators stronger than 10"
│   │   │
│   │   ├─ parseAtom() → Int(5)
│   │   │
│   │   ├─ See '*' (power=20)
│   │   │   ├─ Is 20 > 10?  YES → this operator is ours
│   │   │   ├─ Consume the '*'
│   │   │   ├─ parseExprAbove(threshold=20):
│   │   │   │   ├─ parseAtom() → Int(2)
│   │   │   │   ├─ See EOF (power=0)
│   │   │   │   │   └─ Is 0 > 20?  NO → leave it
│   │   │   │   └─ return Int(2)
│   │   │   └─ Build: Mul(5, 2)
│   │   │
│   │   ├─ See EOF (power=0)
│   │   │   └─ Is 0 > 10?  NO → leave it
│   │   └─ return Mul(5, 2)
│   │
│   └─ Build: Add(3, Mul(5, 2))
│
├─ See EOF (power=0)
│   └─ Is 0 > 0?  NO → leave it
│
└─ return Add(3, Mul(5, 2))

Result: 3 + (5 * 2) = 11 ✓
```

**Why it works**: When `+` (power=10) calls the recursive parser, it says "only grab operators stronger than 10". The `*` (power=20) qualifies, so it grabs the 5 and 2. If there was another `+` after, it would be rejected (10 is NOT > 10).

#### Left-Associativity: `8 - 3 - 2`

The rule `op_power > threshold` (not `>=`) gives us left-to-right evaluation:

```
parseExprAbove(threshold=0):
│
├─ parseAtom() → Int(8)
│
├─ See '-' (power=10)
│   ├─ Is 10 > 0?  YES → grab it
│   ├─ parseExprAbove(threshold=10):
│   │   ├─ parseAtom() → Int(3)
│   │   ├─ See '-' (power=10)
│   │   │   └─ Is 10 > 10?  NO → leave it for caller
│   │   └─ return Int(3)
│   └─ Build: Sub(8, 3)
│
├─ See '-' (power=10)
│   ├─ Is 10 > 0?  YES → grab it
│   ├─ parseExprAbove(threshold=10):
│   │   ├─ parseAtom() → Int(2)
│   │   └─ return Int(2)
│   └─ Build: Sub(Sub(8,3), 2)
│
└─ return Sub(Sub(8,3), 2)

Result: (8 - 3) - 2 = 3 ✓
```

The second `-` has the same power as the first, so it's NOT stronger (`10 > 10` is false). It gets rejected and handled by the outer loop instead, giving us left-to-right.

#### Full Parser Structure

```zig
pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: Allocator,

    pub fn parse(self: *Parser) !*Node {
        var decls: std.ArrayListUnmanaged(*Node) = .empty;

        while (!self.check(.eof)) {
            const decl = try self.parseDeclaration();
            decls.append(self.allocator, decl) catch return error.OutOfMemory;
        }

        return self.createNode(.{
            .root = .{ .decls = decls.toOwnedSlice(self.allocator) catch return error.OutOfMemory },
        });
    }

    fn parseDeclaration(self: *Parser) !*Node {
        const is_pub = self.match(.keyword_pub);

        if (self.check(.keyword_fn)) return self.parseFnDecl(is_pub);
        if (self.check(.keyword_const)) return self.parseConstDecl();
        if (self.check(.keyword_var)) return self.parseVarDecl();

        return error.UnexpectedToken;
    }

    // ... parseFnDecl, parseConstDecl, parseVarDecl, parseBlock, etc.

    fn parseExpression(self: *Parser) !*Node {
        return self.parseExprAbove(POWER.NONE);
    }

    // parseExprAbove as shown above
};
```

### AST Output Example

```
Input: pub fn add(a: i32, b: i32) i32 { return a + b; }

AST:
Root
  FnDecl(pub add)
    params: 2
    Block
      Return
        Binary(+)
          Ident(a)
          Ident(b)
```

---

## Stage 3: ZIR Generation

ZIR (Zig Intermediate Representation) is a flat, linear representation where names are not yet resolved and types are not yet checked.

### ZIR Instructions

```zig
pub const Inst = union(enum) {
    // Constants
    int: i64,
    bool: bool,

    // Arithmetic (+ - * /)
    add: BinOp,
    sub: BinOp,
    mul: BinOp,
    div: BinOp,
    neg: Index,

    // References (unresolved - names as strings)
    decl_ref: []const u8,    // Reference by name
    param_ref: u32,          // Reference by parameter index

    // Declarations
    decl_const: struct { name: []const u8, type_name: ?[]const u8, value: Index },
    decl_var: struct { name: []const u8, type_name: ?[]const u8, value: ?Index },
    decl_fn: DeclFn,

    // Control flow
    block_start: u32,
    block_end: u32,
    ret: ?Index,

    // Calls
    call: struct { callee: []const u8, args: []const Index },
};

pub const BinOp = struct {
    lhs: Index,
    rhs: Index,
};

pub const DeclFn = struct {
    name: []const u8,
    params: []const FnParam,
    return_type: []const u8,
    body_start: Index,
    body_end: Index,
};
```

### ZIR Generator

```zig
pub const Generator = struct {
    instructions: std.ArrayListUnmanaged(Inst),
    allocator: Allocator,
    block_id: u32,

    pub fn generate(self: *Generator, node: *const ast.Node) !void {
        switch (node.*) {
            .root => |r| {
                for (r.items) |item| {
                    try self.generate(item);
                }
            },
            .fn_decl => |f| {
                const start_idx: Index = @intCast(self.instructions.items.len + 1);

                // Emit function declaration
                try self.emit(.{ .decl_fn = .{
                    .name = f.name,
                    .params = try self.convertParams(f.params),
                    .return_type = self.typeToString(f.return_type),
                    .body_start = start_idx,
                    .body_end = 0, // filled in later
                } });

                // Emit block
                const block_id = self.nextBlockId();
                try self.emit(.{ .block_start = block_id });

                if (f.body) |body| {
                    try self.generate(body);
                }

                try self.emit(.{ .block_end = block_id });
            },
            .binary => |b| {
                // Generate operands first
                try self.generate(b.left);
                const lhs: Index = @intCast(self.instructions.items.len - 1);

                try self.generate(b.right);
                const rhs: Index = @intCast(self.instructions.items.len - 1);

                // Emit binary operation
                const op: Inst = switch (b.op) {
                    .add => .{ .add = .{ .lhs = lhs, .rhs = rhs } },
                    .sub => .{ .sub = .{ .lhs = lhs, .rhs = rhs } },
                    .mul => .{ .mul = .{ .lhs = lhs, .rhs = rhs } },
                    .div => .{ .div = .{ .lhs = lhs, .rhs = rhs } },
                    else => unreachable,
                };
                try self.emit(op);
            },
            .identifier => |name| {
                try self.emit(.{ .decl_ref = name });
            },
            // ... more cases
        }
    }
};
```

### ZIR Output Example

```
Input: pub fn add(a: i32, b: i32) i32 { return a + b; }

ZIR:
%0 = decl_fn("add")
%1 = block_start(0)
%2 = param_ref(0)
%3 = param_ref(1)
%4 = add(%2, %3)
%5 = ret(%4)
%6 = block_end(0)
```

Key insight: At this stage, `a` and `b` are just `param_ref(0)` and `param_ref(1)`. The names are resolved, but types aren't checked yet.

---

## Stage 4: Semantic Analysis (Sema)

Sema transforms ZIR into AIR by:
1. Resolving all name references
2. Type checking
3. Type inference

### Type System

```zig
pub const Type = union(enum) {
    int: struct {
        bits: u8,
        signed: bool,
    },
    float: struct {
        bits: u8,
    },
    bool,
    void,
    function,
};
```

### Symbol Tables

```zig
const Symbol = struct {
    name: []const u8,
    type_: Type,
    air_idx: AirIndex,
    is_const: bool,
};

const FnSig = struct {
    name: []const u8,
    params: []const Type,
    return_type: Type,
};

pub const Analyzer = struct {
    globals: std.StringHashMap(Symbol),
    locals: std.StringHashMap(Symbol),
    functions: std.StringHashMap(FnSig),
    current_fn: ?[]const u8,

    // ...
};
```

### Type Resolution

```zig
fn typeFromName(name: []const u8) Type {
    if (std.mem.eql(u8, name, "i32")) return Type{ .int = .{ .bits = 32, .signed = true } };
    if (std.mem.eql(u8, name, "i64")) return Type{ .int = .{ .bits = 64, .signed = true } };
    if (std.mem.eql(u8, name, "bool")) return Type.bool;
    if (std.mem.eql(u8, name, "void")) return Type.void;
    // ... more types
    return Type{ .int = .{ .bits = 32, .signed = true } }; // default
}
```

### Semantic Analysis

```zig
fn analyzeInst(self: *Analyzer, inst: Zir, zir: []const Zir) !AirIndex {
    switch (inst) {
        .add, .sub, .mul, .div => |op| {
            const lhs_air = self.getAirIdx(op.lhs) orelse return SemaError.UndefinedVariable;
            const rhs_air = self.getAirIdx(op.rhs) orelse return SemaError.UndefinedVariable;
            const result_type = Type{ .int = .{ .bits = 64, .signed = true } };

            return self.emit(switch (inst) {
                .add => .{ .add = .{ .lhs = lhs_air, .rhs = rhs_air, .type_ = result_type } },
                .sub => .{ .sub = .{ .lhs = lhs_air, .rhs = rhs_air, .type_ = result_type } },
                .mul => .{ .mul = .{ .lhs = lhs_air, .rhs = rhs_air, .type_ = result_type } },
                .div => .{ .div = .{ .lhs = lhs_air, .rhs = rhs_air, .type_ = result_type } },
                else => unreachable,
            });
        },
        .decl_ref => |name| {
            // Look up variable in scope
            if (self.lookupVar(name)) |sym| {
                return self.emit(.{ .load = .{ .local_idx = sym.air_idx, .type_ = sym.type_ } });
            }
            return SemaError.UndefinedVariable;
        },
        .param_ref => |idx| {
            const param_type = if (idx < self.current_params.len)
                typeFromName(self.current_params[idx].type_name)
            else
                Type{ .int = .{ .bits = 32, .signed = true } };

            return self.emit(.{ .param = .{ .idx = idx, .type_ = param_type } });
        },
        // ... more cases
    }
}
```

### AIR Output Example

```
Input ZIR:
%0 = decl_fn("add")
%1 = block_start(0)
%2 = param_ref(0)
%3 = param_ref(1)
%4 = add(%2, %3)
%5 = ret(%4)
%6 = block_end(0)

Output AIR (with types):
%0 = decl_fn("add"): i32
%1 = block_start(0)
%2 = param(0): i32
%3 = param(1): i32
%4 = add(%2, %3): i64
%5 = ret(%4): i32
%6 = block_end(0)
```

Key difference: Every instruction in AIR has an associated type.

---

## Stage 5: Code Generation

The code generator walks AIR and produces C code.

### Type Mapping

```zig
fn typeToCType(t: Type) []const u8 {
    return switch (t) {
        .int => |i| switch (i.bits) {
            8 => if (i.signed) "int8_t" else "uint8_t",
            16 => if (i.signed) "int16_t" else "uint16_t",
            32 => if (i.signed) "int32_t" else "uint32_t",
            64 => if (i.signed) "int64_t" else "uint64_t",
            else => "int64_t",
        },
        .float => |f| switch (f.bits) {
            32 => "float",
            64 => "double",
            else => "double",
        },
        .bool => "bool",
        .void => "void",
        .function => "void*",
    };
}
```

### Code Generator

```zig
pub const Generator = struct {
    output: std.ArrayListUnmanaged(u8),
    allocator: Allocator,
    indent: usize,
    in_function: bool,

    pub fn generate(self: *Generator, air: []const Air) !void {
        // Header
        try self.write("#include <stdio.h>\n");
        try self.write("#include <stdint.h>\n");
        try self.write("#include <stdbool.h>\n\n");

        // Forward declarations
        for (air) |inst| {
            switch (inst) {
                .decl_fn => |f| {
                    try self.write(typeToCType(f.return_type));
                    try self.print(" {s}(", .{f.name});
                    for (f.params, 0..) |param_type, i| {
                        if (i > 0) try self.write(", ");
                        try self.write(typeToCType(param_type));
                        try self.print(" p{d}", .{i});
                    }
                    try self.write(");\n");
                },
                else => {},
            }
        }
        try self.write("\n");

        // Generate code for each instruction
        for (air, 0..) |_, i| {
            try self.genInst(air, @intCast(i));
        }
    }

    fn genInst(self: *Generator, air: []const Air, idx: AirIndex) !void {
        const inst = air[idx];

        switch (inst) {
            .const_int => |c| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(c.type_));
                    try self.print(" t{d} = {d};\n", .{ idx, c.value });
                }
            },
            .add => |op| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(op.type_));
                    try self.print(" t{d} = t{d} + t{d};\n", .{ idx, op.lhs, op.rhs });
                }
            },
            .decl_fn => |f| {
                try self.write(typeToCType(f.return_type));
                try self.print(" {s}(", .{f.name});
                for (f.params, 0..) |param_type, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(typeToCType(param_type));
                    try self.print(" p{d}", .{i});
                }
                try self.write(") {\n");
                self.in_function = true;
                self.indent = 1;
            },
            .ret => |r| {
                if (self.in_function) {
                    try self.writeIndent();
                    if (r.value) |v| {
                        try self.print("return t{d};\n", .{v});
                    } else {
                        try self.write("return;\n");
                    }
                    self.indent = 0;
                    try self.write("}\n\n");
                    self.in_function = false;
                }
            },
            // ... more cases
        }
    }
};
```

---

## Complete Pipeline Output

Running the compiler on a test program:

```
Input:
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn main() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    const result: i32 = add(x, y);
    return result;
}
```

### Stage by Stage

**AST:**
```
Root
  FnDecl(pub add)
    params: 2
    Block
      Return
        Binary(+)
          Ident(a)
          Ident(b)
  FnDecl(pub main)
    params: 0
    Block
      ConstDecl(x)
        Int(5)
      ConstDecl(y)
        Int(3)
      ConstDecl(result)
        Call
          Ident(add)
          Ident(x)
          Ident(y)
      Return
        Ident(result)
```

**ZIR:**
```
%0 = decl_fn("add")
%1 = block_start(0)
%2 = param_ref(0)
%3 = param_ref(1)
%4 = add(%2, %3)
%5 = ret(%4)
%6 = block_end(0)
%7 = decl_fn("main")
%8 = block_start(1)
%9 = int(5)
%10 = decl_const("x", %9)
%11 = int(3)
%12 = decl_const("y", %11)
%13 = decl_ref("x")
%14 = decl_ref("y")
%15 = call("add", 2 args)
%16 = decl_const("result", %15)
%17 = decl_ref("result")
%18 = ret(%17)
%19 = block_end(1)
```

**AIR:**
```
%0 = decl_fn("add"): i32
%1 = block_start(0)
%2 = param(0): i32
%3 = param(1): i32
%4 = add(%2, %3): i64
%5 = ret(%4): i32
%6 = block_end(0)
%7 = decl_fn("main"): i32
%8 = block_start(1)
%9 = const_int(5: i64)
%10 = decl_const("x", %9): i32
%11 = const_int(3: i64)
%12 = decl_const("y", %11): i32
%13 = load(%10): i32
%14 = load(%12): i32
%15 = call("add", 2 args): i32
%16 = decl_const("result", %15): i32
%17 = load(%16): i32
%18 = ret(%17): i32
%19 = block_end(1)
```

**Generated C:**
```c
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

int32_t add(int32_t p0, int32_t p1);
int32_t main();

int32_t add(int32_t p0, int32_t p1) {
    int32_t t2 = p0;
    int32_t t3 = p1;
    int64_t t4 = t2 + t3;
    return t4;
}

int32_t main() {
    int64_t t9 = 5;
    const int32_t t10 = t9; // x
    int64_t t11 = 3;
    const int32_t t12 = t11; // y
    int32_t t13 = t10;
    int32_t t14 = t12;
    int32_t t15 = add(t13, t14);
    const int32_t t16 = t15; // result
    int32_t t17 = t16;
    return t17;
}
```

The generated C code compiles and runs correctly, returning `8` (5 + 3).

---

## Connection to the Real Zig Compiler

Our mini compiler mirrors the real Zig compiler's architecture:

| Mini Compiler     | Zig Compiler                    |
|-------------------|---------------------------------|
| Lexer             | `lib/std/zig/tokenizer.zig`     |
| Parser            | `lib/std/zig/parse.zig`         |
| AST               | `lib/std/zig/Ast.zig`           |
| ZIR Generator     | `src/AstGen.zig`                |
| Sema              | `src/Sema.zig`                  |
| AIR               | `src/Air.zig`                   |
| Code Generator    | `src/codegen.zig` → LLVM/native |

Key differences:
- **Scale**: Zig handles generics, comptime, error unions, async, and hundreds of other features
- **Backend**: Zig targets multiple architectures via LLVM or its self-hosted backends
- **Optimization**: Zig has sophisticated optimizations at the AIR level

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    MINI ZIG COMPILER ARCHITECTURE                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐                   │
│  │ SOURCE  │───►│  LEXER  │───►│ PARSER  │───►│   ZIR   │                   │
│  │  CODE   │    │         │    │         │    │   GEN   │                   │
│  └─────────┘    └─────────┘    └─────────┘    └────┬────┘                   │
│                                                     │                        │
│                                                     ▼                        │
│  ┌─────────┐    ┌─────────┐                   ┌─────────┐                   │
│  │ C CODE  │◄───│ CODEGEN │◄──────────────────│  SEMA   │                   │
│  │         │    │         │                   │         │                   │
│  └─────────┘    └─────────┘                   └─────────┘                   │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                          WHAT WE LEARNED                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. LEXER: Characters → Tokens                                              │
│     - Keyword lookup with StaticStringMap                                   │
│     - Position tracking for error messages                                  │
│                                                                              │
│  2. PARSER: Tokens → AST                                                    │
│     - Precedence climbing algorithm for expressions                         │
│     - Zig-style function and declaration syntax                             │
│                                                                              │
│  3. ZIR GENERATOR: AST → Flat IR                                            │
│     - Unresolved references (names as strings)                              │
│     - No type information yet                                               │
│                                                                              │
│  4. SEMA: ZIR → AIR                                                         │
│     - Name resolution via symbol tables                                     │
│     - Type checking and inference                                           │
│                                                                              │
│  5. CODEGEN: AIR → C                                                        │
│     - Type-aware code generation                                            │
│     - Maps Zig types to C types (i32 → int32_t)                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

This ~1000-line compiler demonstrates the fundamental concepts behind the real Zig compiler. The key insight is the **staged lowering**: each stage removes complexity and makes the next stage's job easier.

---

## Running the Code

```bash
cd mini-compiler
zig build run
```

The compiler will show all intermediate stages and produce valid C code.

---

*Source code: [github.com/...](https://github.com/...)*
