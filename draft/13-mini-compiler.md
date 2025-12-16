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
├── build.zig           # Build configuration
└── src/
    ├── main.zig        # Entry point - ties everything together
    ├── token.zig       # Token type definitions
    ├── lexer.zig       # Stage 1: Tokenizer
    ├── ast.zig         # AST node definitions
    ├── parser.zig      # Stage 2: Parser
    ├── zir.zig         # Stage 3: ZIR (Zig IR) generation
    ├── sema.zig        # Stage 4: Semantic Analysis
    ├── air.zig         # AIR (Analyzed IR) definitions
    └── codegen.zig     # Stage 5: C Code Generation
```

Build and run:
```bash
zig build run
```

---

## Stage 1: The Lexer

The lexer breaks source text into tokens - the smallest meaningful units of Zig syntax.

### Token Types

```zig
pub const TokenType = enum {
    // Keywords
    kw_fn,
    kw_pub,
    kw_const,
    kw_var,
    kw_return,
    kw_if,
    kw_else,
    kw_while,
    kw_true,
    kw_false,

    // Types
    type_i8, type_i16, type_i32, type_i64,
    type_u8, type_u16, type_u32, type_u64,
    type_f32, type_f64,
    type_bool,
    type_void,

    // Literals
    int_literal,
    float_literal,

    // Operators
    plus,      // +
    minus,     // -
    star,      // *
    slash,     // /
    eq,        // =
    eq_eq,     // ==
    bang_eq,   // !=
    less,      // <
    greater,   // >

    // Delimiters
    lparen, rparen,     // ( )
    lbrace, rbrace,     // { }
    colon,              // :
    semicolon,          // ;
    comma,              // ,

    // Other
    identifier,
    eof,
    invalid,
};
```

### Keyword Lookup

Zig's `comptime` makes keyword lookup elegant:

```zig
pub fn getKeyword(text: []const u8) ?TokenType {
    const keywords = std.StaticStringMap(TokenType).initComptime(.{
        .{ "fn", .kw_fn },
        .{ "pub", .kw_pub },
        .{ "const", .kw_const },
        .{ "var", .kw_var },
        .{ "return", .kw_return },
        .{ "if", .kw_if },
        .{ "else", .kw_else },
        .{ "while", .kw_while },
        .{ "true", .kw_true },
        .{ "false", .kw_false },
        // Type keywords
        .{ "i32", .type_i32 },
        .{ "i64", .type_i64 },
        .{ "bool", .type_bool },
        .{ "void", .type_void },
        // ... more types
    });
    return keywords.get(text);
}
```

### Lexer Implementation

```zig
pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
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

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();

        if (self.pos >= self.source.len) {
            return .{ .type = .eof, .lexeme = "", .line = self.line };
        }

        const c = self.peek();

        // Identifiers and keywords
        if (isAlpha(c)) return self.scanIdentifier();

        // Numbers
        if (isDigit(c)) return self.scanNumber();

        // Two-character operators: ==, !=, etc.
        if (c == '=' and self.peekNext() == '=') {
            _ = self.advance();
            _ = self.advance();
            return .{ .type = .eq_eq, .lexeme = "==", .line = self.line };
        }

        // Single character tokens
        _ = self.advance();
        const token_type: TokenType = switch (c) {
            '+' => .plus,
            '-' => .minus,
            '*' => .star,
            '/' => .slash,
            '=' => .eq,
            '(' => .lparen,
            ')' => .rparen,
            '{' => .lbrace,
            '}' => .rbrace,
            ':' => .colon,
            ';' => .semicolon,
            ',' => .comma,
            else => .invalid,
        };

        return .{ .type = token_type, .lexeme = self.source[self.pos-1..self.pos], .line = self.line };
    }

    fn scanIdentifier(self: *Lexer) Token {
        const start = self.pos;
        while (isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }
        const text = self.source[start..self.pos];

        // Check if it's a keyword
        if (token.getKeyword(text)) |kw| {
            return .{ .type = kw, .lexeme = text, .line = self.line };
        }

        return .{ .type = .identifier, .lexeme = text, .line = self.line };
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
│ kw_pub         │ "pub"   │ 1    │
│ kw_fn          │ "fn"    │ 1    │
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
    if_stmt: IfStmt,
    while_stmt: WhileStmt,
    expr_stmt: ExprStmt,

    // Expressions
    int_literal: i64,
    float_literal: f64,
    bool_literal: bool,
    identifier: []const u8,
    binary: Binary,
    unary: Unary,
    call: Call,
    grouped: *Node,

    // Top-level
    root: Root,
};

pub const FnDecl = struct {
    name: []const u8,
    params: []const Param,
    return_type: ?TypeExpr,
    body: ?*Node,
    is_pub: bool,
};

pub const Binary = struct {
    op: BinaryOp,
    left: *Node,
    right: *Node,
};

pub const BinaryOp = enum {
    add, sub, mul, div,
    eq, neq, lt, lte, gt, gte,
};
```

### Recursive Descent Parser

```zig
pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: Allocator,

    pub fn parse(self: *Parser) !*Node {
        var items: std.ArrayListUnmanaged(*Node) = .empty;

        while (!self.isAtEnd()) {
            const item = try self.parseTopLevel();
            try items.append(self.allocator, item);
        }

        return self.createNode(.{ .root = .{
            .items = try items.toOwnedSlice(self.allocator),
        } });
    }

    fn parseTopLevel(self: *Parser) !*Node {
        const is_pub = self.match(.kw_pub);

        if (self.check(.kw_fn)) {
            return self.parseFnDecl(is_pub);
        }
        if (self.check(.kw_const)) {
            return self.parseConstDecl();
        }
        if (self.check(.kw_var)) {
            return self.parseVarDecl();
        }

        return ParseError.UnexpectedToken;
    }

    fn parseFnDecl(self: *Parser, is_pub: bool) !*Node {
        _ = try self.expect(.kw_fn);
        const name = try self.expect(.identifier);
        _ = try self.expect(.lparen);

        // Parse parameters
        var params: std.ArrayListUnmanaged(Param) = .empty;
        while (!self.check(.rparen)) {
            const param_name = try self.expect(.identifier);
            _ = try self.expect(.colon);
            const param_type = try self.parseType();
            try params.append(self.allocator, .{
                .name = param_name.lexeme,
                .type_expr = param_type,
            });
            if (!self.match(.comma)) break;
        }
        _ = try self.expect(.rparen);

        // Return type
        const return_type = try self.parseType();

        // Body
        const body = try self.parseBlock();

        return self.createNode(.{ .fn_decl = .{
            .name = name.lexeme,
            .params = try params.toOwnedSlice(self.allocator),
            .return_type = return_type,
            .body = body,
            .is_pub = is_pub,
        } });
    }

    // Expression parsing with precedence
    fn parseExpr(self: *Parser) !*Node {
        return self.parseAdditive();
    }

    fn parseAdditive(self: *Parser) !*Node {
        var left = try self.parseMultiplicative();

        while (self.match(.plus) or self.match(.minus)) {
            const op: BinaryOp = if (self.previous().type == .plus) .add else .sub;
            const right = try self.parseMultiplicative();
            left = try self.createNode(.{ .binary = .{
                .op = op,
                .left = left,
                .right = right,
            } });
        }

        return left;
    }

    fn parseMultiplicative(self: *Parser) !*Node {
        var left = try self.parseUnary();

        while (self.match(.star) or self.match(.slash)) {
            const op: BinaryOp = if (self.previous().type == .star) .mul else .div;
            const right = try self.parseUnary();
            left = try self.createNode(.{ .binary = .{
                .op = op,
                .left = left,
                .right = right,
            } });
        }

        return left;
    }
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
    float: f64,
    bool: bool,

    // Arithmetic
    add: BinaryOp,
    sub: BinaryOp,
    mul: BinaryOp,
    div: BinaryOp,
    neg: Index,

    // Comparisons
    cmp_eq: BinaryOp,
    cmp_neq: BinaryOp,
    cmp_lt: BinaryOp,
    cmp_gt: BinaryOp,

    // References (unresolved)
    decl_ref: []const u8,    // Reference by name
    param_ref: u32,          // Reference by parameter index

    // Declarations
    decl_const: DeclConst,
    decl_var: DeclVar,
    decl_fn: DeclFn,

    // Control flow
    block_start: u32,
    block_end: u32,
    ret: ?Index,
    cond_br: CondBr,

    // Other
    store: Store,
    call: Call,
};

pub const BinaryOp = struct {
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
│     - Recursive descent with precedence handling                            │
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
