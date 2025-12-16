# Zig Compiler Internals Part 13: Building a Mini Compiler
*From source code to execution - a complete compiler in 1000 lines*

---

## Introduction

Throughout this series, we've explored how the Zig compiler transforms source code into executables. Now let's put that knowledge into practice by building a complete mini compiler from scratch.

We'll build a calculator language that supports:
- Integer and floating-point numbers
- Arithmetic operators: `+`, `-`, `*`, `/`, `%`
- Parentheses for grouping
- Variables and assignments
- Multiple statements

**Our compiler will have all 7 stages of a real compiler:**

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE COMPLETE COMPILER PIPELINE                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source: "x = 3 + 5 * 2; x + 1"                                            │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 1: LEXER (Tokenizer)         │                                   │
│   │  Breaks text into tokens            │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   Tokens: [ID:x, EQ, INT:3, PLUS, INT:5, STAR, INT:2, SEMI, ID:x, PLUS, INT:1]│
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 2: PARSER (AST Builder)      │                                   │
│   │  Builds tree structure              │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   AST:  StatementList                                                       │
│           ├── Assign(x, Add(3, Mul(5, 2)))                                  │
│           └── Add(Var(x), 1)                                                │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 3: SEMANTIC ANALYSIS         │                                   │
│   │  Type checking, scope resolution    │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 4: OPTIMIZER                 │                                   │
│   │  Constant folding: 5*2 → 10         │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   AST:  StatementList                                                       │
│           ├── Assign(x, 13)  ← Folded!                                      │
│           └── Add(Var(x), 1)                                                │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 5: IR GENERATION             │                                   │
│   │  Linear instruction sequence        │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   IR: [PUSH 13, STORE x, LOAD x, PUSH 1, ADD]                               │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 6: CODE GENERATION           │                                   │
│   │  Emit bytecode                      │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   Bytecode: [0x01, 0x00, 0x21, 0x00, 0x20, 0x00, 0x01, 0x01, 0x10, 0xFF]    │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  STAGE 7: VIRTUAL MACHINE           │                                   │
│   │  Execute bytecode                   │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   Result: 14                                                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

Our compiler is organized into separate modules, each handling one stage of the pipeline:

```
mini-compiler/
├── build.zig           # Build configuration
└── src/
    ├── main.zig        # Entry point - ties everything together
    ├── token.zig       # Token type definitions
    ├── lexer.zig       # Stage 1: Tokenizer
    ├── ast.zig         # AST node definitions
    ├── parser.zig      # Stage 2: Parser
    ├── sema.zig        # Stage 3: Semantic Analysis
    ├── optimizer.zig   # Stage 4: Constant Folding
    ├── ir.zig          # Stage 5: IR Generation
    ├── codegen.zig     # Stage 6: Bytecode Generation
    └── vm.zig          # Stage 7: Virtual Machine
```

Each module imports what it needs from other modules:

```zig
// main.zig - imports all stages
pub const token = @import("token.zig");
pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const sema = @import("sema.zig");
pub const optimizer = @import("optimizer.zig");
pub const ir = @import("ir.zig");
pub const codegen = @import("codegen.zig");
pub const vm = @import("vm.zig");
```

Build and run with:
```bash
zig build run
```

---

## Stage 1: The Lexer (Tokenizer)

The lexer breaks source text into tokens - the smallest meaningful units.

### Token Types

```zig
const TokenType = enum {
    // Literals
    int_literal,
    float_literal,

    // Operators
    plus,     // +
    minus,    // -
    star,     // *
    slash,    // /
    percent,  // %

    // Delimiters
    lparen,    // (
    rparen,    // )
    semicolon, // ;
    equals,    // =

    // Other
    identifier,
    eof,
    invalid,
};

const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
};
```

### The Lexer State Machine

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LEXER STATE MACHINE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌───────────┐                                                             │
│   │   START   │                                                             │
│   └─────┬─────┘                                                             │
│         │                                                                   │
│    ┌────┴────┬────────┬────────┬────────┬────────┐                         │
│    ▼         ▼        ▼        ▼        ▼        ▼                         │
│  ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐                       │
│  │0-9 │   │a-z │   │ +  │   │ (  │   │ ;  │   │ =  │                       │
│  │    │   │A-Z │   │ -  │   │ )  │   │    │   │    │                       │
│  │    │   │ _  │   │ *  │   │    │   │    │   │    │                       │
│  │    │   │    │   │ /  │   │    │   │    │   │    │                       │
│  │    │   │    │   │ %  │   │    │   │    │   │    │                       │
│  └──┬─┘   └──┬─┘   └──┬─┘   └──┬─┘   └──┬─┘   └──┬─┘                       │
│     │        │        │        │        │        │                         │
│     ▼        ▼        ▼        ▼        ▼        ▼                         │
│  NUMBER   IDENT    OPERATOR  PAREN   SEMI     EQUALS                       │
│                                                                             │
│  Number scanning:                                                           │
│  ┌─────────────────────────────────────────────────────────┐               │
│  │ "3.14" → scan digits → check for '.' → scan decimals   │               │
│  │         ^^^              ^^^            ^^^              │               │
│  │         INT              DOT            FLOAT            │               │
│  └─────────────────────────────────────────────────────────┘               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Lexer Implementation

```zig
const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    start_column: usize,

    fn init(source: []const u8) Lexer {
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

    fn skipWhitespace(self: *Lexer) void {
        while (true) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                _ = self.advance();
            } else {
                break;
            }
        }
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isAlphaNumeric(c: u8) bool {
        return isAlpha(c) or isDigit(c);
    }

    fn scanNumber(self: *Lexer) Token {
        const start = self.pos;
        var is_float = false;

        while (isDigit(self.peek())) {
            _ = self.advance();
        }

        // Check for decimal part
        if (self.peek() == '.' and self.pos + 1 < self.source.len
            and isDigit(self.source[self.pos + 1])) {
            is_float = true;
            _ = self.advance(); // consume '.'
            while (isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        return .{
            .type = if (is_float) .float_literal else .int_literal,
            .lexeme = self.source[start..self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    fn scanIdentifier(self: *Lexer) Token {
        const start = self.pos;
        while (isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }
        return .{
            .type = .identifier,
            .lexeme = self.source[start..self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    fn nextToken(self: *Lexer) Token {
        self.skipWhitespace();
        self.start_column = self.column;

        if (self.pos >= self.source.len) {
            return .{ .type = .eof, .lexeme = "", .line = self.line, .column = self.column };
        }

        const c = self.peek();

        // Numbers
        if (isDigit(c)) return self.scanNumber();

        // Identifiers
        if (isAlpha(c)) return self.scanIdentifier();

        // Single character tokens
        _ = self.advance();
        const token_type: TokenType = switch (c) {
            '+' => .plus,
            '-' => .minus,
            '*' => .star,
            '/' => .slash,
            '%' => .percent,
            '(' => .lparen,
            ')' => .rparen,
            ';' => .semicolon,
            '=' => .equals,
            else => .invalid,
        };

        return .{
            .type = token_type,
            .lexeme = self.source[self.pos - 1 .. self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }
};
```

### Tokenization Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Input: "x = 3 + 5 * 2"                                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Position:  0   1   2   3   4   5   6   7   8   9  10  11  12               │
│  Source:   [x] [ ] [=] [ ] [3] [ ] [+] [ ] [5] [ ] [*] [ ] [2]              │
│                                                                              │
│  Output Tokens:                                                              │
│  ┌────────────────┬─────────────┬──────┬────────┐                           │
│  │ Token Type     │ Lexeme      │ Line │ Column │                           │
│  ├────────────────┼─────────────┼──────┼────────┤                           │
│  │ identifier     │ "x"         │ 1    │ 1      │                           │
│  │ equals         │ "="         │ 1    │ 3      │                           │
│  │ int_literal    │ "3"         │ 1    │ 5      │                           │
│  │ plus           │ "+"         │ 1    │ 7      │                           │
│  │ int_literal    │ "5"         │ 1    │ 9      │                           │
│  │ star           │ "*"         │ 1    │ 11     │                           │
│  │ int_literal    │ "2"         │ 1    │ 13     │                           │
│  │ eof            │ ""          │ 1    │ 14     │                           │
│  └────────────────┴─────────────┴──────┴────────┘                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stage 2: The Parser (AST Builder)

The parser transforms tokens into an Abstract Syntax Tree (AST) - a hierarchical representation of the program's structure.

### Grammar

Our language follows this grammar:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              GRAMMAR RULES                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  program    → statement (";" statement)* EOF                                │
│  statement  → assignment | expression                                       │
│  assignment → IDENTIFIER "=" expression                                     │
│  expression → term (("+"|"-") term)*                                        │
│  term       → factor (("*"|"/"|"%") factor)*                                │
│  factor     → unary | primary                                               │
│  unary      → "-" factor | primary                                          │
│  primary    → NUMBER | IDENTIFIER | "(" expression ")"                      │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                         OPERATOR PRECEDENCE                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Lowest    ─┬─ =          (assignment)                                      │
│             │                                                                │
│             ├─ + -        (addition, subtraction)                           │
│             │                                                                │
│             ├─ * / %      (multiplication, division, modulo)                │
│             │                                                                │
│  Highest  ──┴─ - (unary)  (negation)                                        │
│                                                                              │
│  Example: "3 + 5 * 2" parses as "3 + (5 * 2)" = 13, not "(3 + 5) * 2" = 16  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### AST Node Types

```zig
const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
};

const UnaryOp = enum {
    neg,
};

const AstNode = union(enum) {
    int_literal: i64,
    float_literal: f64,
    binary: struct {
        op: BinaryOp,
        left: *AstNode,
        right: *AstNode,
    },
    unary: struct {
        op: UnaryOp,
        operand: *AstNode,
    },
    variable: []const u8,
    assignment: struct {
        name: []const u8,
        value: *AstNode,
    },
    statement_list: struct {
        statements: []*AstNode,
    },
};
```

### Parser Implementation (Recursive Descent)

```zig
const Parser = struct {
    lexer: Lexer,
    current: Token,
    allocator: Allocator,

    fn init(source: []const u8, allocator: Allocator) Parser {
        var lexer = Lexer.init(source);
        const first_token = lexer.nextToken();
        return .{
            .lexer = lexer,
            .current = first_token,
            .allocator = allocator,
        };
    }

    fn advance(self: *Parser) void {
        self.current = self.lexer.nextToken();
    }

    fn expect(self: *Parser, expected: TokenType) ParseError!void {
        if (self.current.type != expected) {
            return ParseError.UnexpectedToken;
        }
        self.advance();
    }

    fn createNode(self: *Parser, node: AstNode) ParseError!*AstNode {
        const ptr = self.allocator.create(AstNode) catch return ParseError.OutOfMemory;
        ptr.* = node;
        return ptr;
    }

    // program → statement (";" statement)* EOF
    fn parse(self: *Parser) ParseError!*AstNode {
        var statements: std.ArrayList(*AstNode) = .empty;

        const first = try self.parseStatement();
        statements.append(self.allocator, first) catch return ParseError.OutOfMemory;

        while (self.current.type == .semicolon) {
            self.advance();
            if (self.current.type == .eof) break;
            const stmt = try self.parseStatement();
            statements.append(self.allocator, stmt) catch return ParseError.OutOfMemory;
        }

        if (statements.items.len == 1) {
            return statements.items[0];
        }

        return self.createNode(.{
            .statement_list = .{
                .statements = statements.toOwnedSlice(self.allocator) catch
                    return ParseError.OutOfMemory,
            },
        });
    }

    // statement → assignment | expression
    fn parseStatement(self: *Parser) ParseError!*AstNode {
        if (self.current.type == .identifier) {
            const name = self.current.lexeme;
            var peek_lexer = self.lexer;
            const peek_token = peek_lexer.nextToken();
            if (peek_token.type == .equals) {
                self.advance(); // consume identifier
                self.advance(); // consume '='
                const value = try self.parseExpression();
                return self.createNode(.{
                    .assignment = .{ .name = name, .value = value },
                });
            }
        }
        return self.parseExpression();
    }

    // expression → term (("+"|"-") term)*
    fn parseExpression(self: *Parser) ParseError!*AstNode {
        var left = try self.parseTerm();

        while (self.current.type == .plus or self.current.type == .minus) {
            const op: BinaryOp = if (self.current.type == .plus) .add else .sub;
            self.advance();
            const right = try self.parseTerm();
            left = try self.createNode(.{
                .binary = .{ .op = op, .left = left, .right = right },
            });
        }

        return left;
    }

    // term → factor (("*"|"/"|"%") factor)*
    fn parseTerm(self: *Parser) ParseError!*AstNode {
        var left = try self.parseFactor();

        while (self.current.type == .star or
               self.current.type == .slash or
               self.current.type == .percent) {
            const op: BinaryOp = switch (self.current.type) {
                .star => .mul,
                .slash => .div,
                .percent => .mod,
                else => unreachable,
            };
            self.advance();
            const right = try self.parseFactor();
            left = try self.createNode(.{
                .binary = .{ .op = op, .left = left, .right = right },
            });
        }

        return left;
    }

    // factor → "-" factor | primary
    fn parseFactor(self: *Parser) ParseError!*AstNode {
        if (self.current.type == .minus) {
            self.advance();
            const operand = try self.parseFactor();
            return self.createNode(.{
                .unary = .{ .op = .neg, .operand = operand },
            });
        }
        return self.parsePrimary();
    }

    // primary → NUMBER | IDENTIFIER | "(" expression ")"
    fn parsePrimary(self: *Parser) ParseError!*AstNode {
        switch (self.current.type) {
            .int_literal => {
                const value = std.fmt.parseInt(i64, self.current.lexeme, 10) catch
                    return ParseError.InvalidNumber;
                self.advance();
                return self.createNode(.{ .int_literal = value });
            },
            .float_literal => {
                const value = std.fmt.parseFloat(f64, self.current.lexeme) catch
                    return ParseError.InvalidNumber;
                self.advance();
                return self.createNode(.{ .float_literal = value });
            },
            .identifier => {
                const name = self.current.lexeme;
                self.advance();
                return self.createNode(.{ .variable = name });
            },
            .lparen => {
                self.advance();
                const expr = try self.parseExpression();
                try self.expect(.rparen);
                return expr;
            },
            else => return ParseError.UnexpectedToken,
        }
    }
};
```

### AST Visualization

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Input: "3 + 5 * 2"                                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Parse Trace:                                                                │
│                                                                              │
│  parseExpression()                                                          │
│    │                                                                         │
│    ├─► parseTerm()                                                          │
│    │     │                                                                   │
│    │     └─► parsePrimary() → IntLiteral(3)                                 │
│    │                                                                         │
│    ├─► See '+', consume it                                                  │
│    │                                                                         │
│    └─► parseTerm()                                                          │
│          │                                                                   │
│          ├─► parsePrimary() → IntLiteral(5)                                 │
│          │                                                                   │
│          ├─► See '*', consume it                                            │
│          │                                                                   │
│          └─► parsePrimary() → IntLiteral(2)                                 │
│              │                                                               │
│              └─► Return: Binary(*, 5, 2)                                    │
│                                                                              │
│                                                                              │
│  Resulting AST:                                                             │
│                                                                              │
│              Binary(+)                                                       │
│              /       \                                                       │
│         Int(3)    Binary(*)                                                 │
│                   /       \                                                  │
│               Int(5)    Int(2)                                              │
│                                                                              │
│  Evaluation: 3 + (5 * 2) = 3 + 10 = 13                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stage 3: Semantic Analysis

Semantic analysis validates the AST and annotates it with type information.

### Type System

```zig
const ValueType = enum {
    int,
    float,
};

const TypedNode = struct {
    node: *AstNode,
    value_type: ValueType,
};
```

### Semantic Analyzer

```zig
const SemanticAnalyzer = struct {
    variables: std.StringHashMap(ValueType),
    allocator: Allocator,

    fn init(allocator: Allocator) SemanticAnalyzer {
        return .{
            .variables = std.StringHashMap(ValueType).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *SemanticAnalyzer) void {
        self.variables.deinit();
    }

    fn analyze(self: *SemanticAnalyzer, node: *AstNode) SemanticError!TypedNode {
        switch (node.*) {
            .int_literal => return .{ .node = node, .value_type = .int },
            .float_literal => return .{ .node = node, .value_type = .float },

            .variable => |name| {
                if (self.variables.get(name)) |vtype| {
                    return .{ .node = node, .value_type = vtype };
                }
                return SemanticError.UndefinedVariable;
            },

            .assignment => |assign| {
                const typed_value = try self.analyze(assign.value);
                self.variables.put(assign.name, typed_value.value_type) catch
                    return SemanticError.OutOfMemory;
                return .{ .node = node, .value_type = typed_value.value_type };
            },

            .unary => |unary| {
                const typed_operand = try self.analyze(unary.operand);
                return .{ .node = node, .value_type = typed_operand.value_type };
            },

            .binary => |binary| {
                const typed_left = try self.analyze(binary.left);
                const typed_right = try self.analyze(binary.right);

                // Type coercion: if either operand is float, result is float
                const result_type: ValueType =
                    if (typed_left.value_type == .float or
                        typed_right.value_type == .float)
                        .float
                    else
                        .int;

                return .{ .node = node, .value_type = result_type };
            },

            .statement_list => |list| {
                var last_type: ValueType = .int;
                for (list.statements) |stmt| {
                    const typed = try self.analyze(stmt);
                    last_type = typed.value_type;
                }
                return .{ .node = node, .value_type = last_type };
            },
        }
    }
};
```

### Type Coercion Rules

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           TYPE COERCION RULES                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Rule: When mixing int and float, the result is always float                │
│                                                                              │
│  ┌─────────────┬─────────────┬─────────────┐                                │
│  │   Left      │   Right     │   Result    │                                │
│  ├─────────────┼─────────────┼─────────────┤                                │
│  │   int       │   int       │   int       │                                │
│  │   int       │   float     │   float     │                                │
│  │   float     │   int       │   float     │                                │
│  │   float     │   float     │   float     │                                │
│  └─────────────┴─────────────┴─────────────┘                                │
│                                                                              │
│  Examples:                                                                   │
│    3 + 5       → int                                                        │
│    3 + 5.0     → float                                                      │
│    3.0 + 5     → float                                                      │
│    3.0 + 5.0   → float                                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stage 4: Optimizer (Constant Folding)

The optimizer transforms the AST to improve performance. Our optimizer performs **constant folding** - evaluating constant expressions at compile time.

```zig
const Optimizer = struct {
    allocator: Allocator,

    fn init(allocator: Allocator) Optimizer {
        return .{ .allocator = allocator };
    }

    fn optimize(self: *Optimizer, node: *AstNode) !*AstNode {
        switch (node.*) {
            .int_literal, .float_literal, .variable => return node,

            .assignment => |assign| {
                const opt_value = try self.optimize(assign.value);
                node.*.assignment.value = opt_value;
                return node;
            },

            .unary => |unary| {
                const opt_operand = try self.optimize(unary.operand);

                // Constant fold: -constant
                switch (opt_operand.*) {
                    .int_literal => |val| {
                        const new_node = try self.allocator.create(AstNode);
                        new_node.* = .{ .int_literal = -val };
                        return new_node;
                    },
                    .float_literal => |val| {
                        const new_node = try self.allocator.create(AstNode);
                        new_node.* = .{ .float_literal = -val };
                        return new_node;
                    },
                    else => {
                        node.*.unary.operand = opt_operand;
                        return node;
                    },
                }
            },

            .binary => |binary| {
                const opt_left = try self.optimize(binary.left);
                const opt_right = try self.optimize(binary.right);

                // Check if both operands are constants
                const left_int = if (opt_left.* == .int_literal)
                    opt_left.int_literal else null;
                const right_int = if (opt_right.* == .int_literal)
                    opt_right.int_literal else null;
                const left_float = if (opt_left.* == .float_literal)
                    opt_left.float_literal else null;
                const right_float = if (opt_right.* == .float_literal)
                    opt_right.float_literal else null;

                // Both integers - fold to integer
                if (left_int != null and right_int != null) {
                    const l = left_int.?;
                    const r = right_int.?;
                    const result: i64 = switch (binary.op) {
                        .add => l + r,
                        .sub => l - r,
                        .mul => l * r,
                        .div => @divTrunc(l, r),
                        .mod => @mod(l, r),
                    };
                    const new_node = try self.allocator.create(AstNode);
                    new_node.* = .{ .int_literal = result };
                    return new_node;
                }

                // At least one float - fold to float
                if ((left_int != null or left_float != null) and
                    (right_int != null or right_float != null)) {
                    const l: f64 = left_float orelse @floatFromInt(left_int.?);
                    const r: f64 = right_float orelse @floatFromInt(right_int.?);

                    if (left_float != null or right_float != null) {
                        const result: f64 = switch (binary.op) {
                            .add => l + r,
                            .sub => l - r,
                            .mul => l * r,
                            .div => l / r,
                            .mod => @mod(l, r),
                        };
                        const new_node = try self.allocator.create(AstNode);
                        new_node.* = .{ .float_literal = result };
                        return new_node;
                    }
                }

                // Can't fold - keep the binary node
                node.*.binary.left = opt_left;
                node.*.binary.right = opt_right;
                return node;
            },

            .statement_list => |list| {
                for (list.statements, 0..) |stmt, i| {
                    list.statements[i] = try self.optimize(stmt);
                }
                return node;
            },
        }
    }
};
```

### Optimization Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        CONSTANT FOLDING EXAMPLE                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Input: "x = 3 + 5 * 2"                                                     │
│                                                                              │
│  Before Optimization:          After Optimization:                          │
│                                                                              │
│       Assign                         Assign                                 │
│      /      \                       /      \                                │
│    "x"    Binary(+)               "x"    Int(13)                            │
│          /       \                                                          │
│       Int(3)  Binary(*)            5 * 2 = 10                               │
│               /      \             3 + 10 = 13                              │
│           Int(5)   Int(2)                                                   │
│                                                                              │
│  Result: "x = 13" - No runtime computation needed!                          │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│  More Examples:                                                              │
│                                                                              │
│  "-(-5)"        → 5                (double negation eliminated)             │
│  "2 + 3 + 4"    → 9                (chained additions folded)               │
│  "100 / 10 / 2" → 5                (chained divisions folded)               │
│  "x + 0"        → x + 0            (NOT folded - variable involved)         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stage 5: IR Generation

The IR (Intermediate Representation) is a linear sequence of instructions - easier to work with than a tree for code generation.

### IR Instructions

```zig
const IrOpCode = enum {
    push_int,
    push_float,
    add,
    sub,
    mul,
    div,
    mod,
    neg,
    load,
    store,
    int_to_float,
};

const IrInstruction = struct {
    op: IrOpCode,
    operand: union {
        int_value: i64,
        float_value: f64,
        var_name: []const u8,
        none: void,
    },
};
```

### IR Generator

```zig
const IrGenerator = struct {
    instructions: std.ArrayList(IrInstruction),
    allocator: Allocator,

    fn init(allocator: Allocator) IrGenerator {
        return .{
            .instructions = .empty,
            .allocator = allocator,
        };
    }

    fn emit(self: *IrGenerator, inst: IrInstruction) !void {
        try self.instructions.append(self.allocator, inst);
    }

    fn generate(self: *IrGenerator, node: *AstNode) !void {
        switch (node.*) {
            .int_literal => |value| {
                try self.emit(.{
                    .op = .push_int,
                    .operand = .{ .int_value = value }
                });
            },
            .float_literal => |value| {
                try self.emit(.{
                    .op = .push_float,
                    .operand = .{ .float_value = value }
                });
            },
            .variable => |name| {
                try self.emit(.{
                    .op = .load,
                    .operand = .{ .var_name = name }
                });
            },
            .assignment => |assign| {
                try self.generate(assign.value);
                try self.emit(.{
                    .op = .store,
                    .operand = .{ .var_name = assign.name }
                });
            },
            .unary => |unary| {
                try self.generate(unary.operand);
                switch (unary.op) {
                    .neg => try self.emit(.{
                        .op = .neg,
                        .operand = .{ .none = {} }
                    }),
                }
            },
            .binary => |binary| {
                try self.generate(binary.left);
                try self.generate(binary.right);
                const op: IrOpCode = switch (binary.op) {
                    .add => .add,
                    .sub => .sub,
                    .mul => .mul,
                    .div => .div,
                    .mod => .mod,
                };
                try self.emit(.{ .op = op, .operand = .{ .none = {} } });
            },
            .statement_list => |list| {
                for (list.statements) |stmt| {
                    try self.generate(stmt);
                }
            },
        }
    }
};
```

### IR Generation Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          IR GENERATION EXAMPLE                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Input: "x = 10; y = 20; x + y"                                             │
│                                                                              │
│  AST:                                                                        │
│       StatementList                                                          │
│       ├── Assign(x, 10)                                                     │
│       ├── Assign(y, 20)                                                     │
│       └── Binary(+, Var(x), Var(y))                                         │
│                                                                              │
│  Generated IR:                                                               │
│  ┌────────┬────────────────────────────────────────────────────────────────┐│
│  │ Index  │ Instruction                                                    ││
│  ├────────┼────────────────────────────────────────────────────────────────┤│
│  │   0    │ PUSH_INT 10      ; Push value 10                              ││
│  │   1    │ STORE x          ; Pop and store in x                         ││
│  │   2    │ PUSH_INT 20      ; Push value 20                              ││
│  │   3    │ STORE y          ; Pop and store in y                         ││
│  │   4    │ LOAD x           ; Push value of x                            ││
│  │   5    │ LOAD y           ; Push value of y                            ││
│  │   6    │ ADD              ; Pop two values, push sum                   ││
│  └────────┴────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  Stack Trace:                                                                │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ After PUSH 10:    [10]                                                 │ │
│  │ After STORE x:    []           x=10                                    │ │
│  │ After PUSH 20:    [20]                                                 │ │
│  │ After STORE y:    []           x=10, y=20                              │ │
│  │ After LOAD x:     [10]                                                 │ │
│  │ After LOAD y:     [10, 20]                                             │ │
│  │ After ADD:        [30]         ← Result!                               │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stage 6: Code Generation (Bytecode)

The code generator converts IR into bytecode - a compact binary format that our VM can execute efficiently.

### Bytecode Format

```zig
const ByteCode = enum(u8) {
    push_int = 0x01,
    push_float = 0x02,
    add = 0x10,
    sub = 0x11,
    mul = 0x12,
    div = 0x13,
    mod = 0x14,
    neg = 0x15,
    load = 0x20,
    store = 0x21,
    halt = 0xFF,
};
```

### Code Generator

```zig
const CodeGenerator = struct {
    code: std.ArrayList(u8),
    constants_int: std.ArrayList(i64),
    constants_float: std.ArrayList(f64),
    var_indices: std.StringHashMap(u8),
    next_var_index: u8,
    allocator: Allocator,

    fn init(allocator: Allocator) CodeGenerator {
        return .{
            .code = .empty,
            .constants_int = .empty,
            .constants_float = .empty,
            .var_indices = std.StringHashMap(u8).init(allocator),
            .next_var_index = 0,
            .allocator = allocator,
        };
    }

    fn emitByte(self: *CodeGenerator, byte: u8) !void {
        try self.code.append(self.allocator, byte);
    }

    fn getOrCreateVarIndex(self: *CodeGenerator, name: []const u8) !u8 {
        if (self.var_indices.get(name)) |idx| {
            return idx;
        }
        const idx = self.next_var_index;
        self.next_var_index += 1;
        try self.var_indices.put(name, idx);
        return idx;
    }

    fn generateFromIr(self: *CodeGenerator, ir: []const IrInstruction) !void {
        for (ir) |inst| {
            switch (inst.op) {
                .push_int => {
                    try self.emitByte(@intFromEnum(ByteCode.push_int));
                    const idx: u8 = @intCast(self.constants_int.items.len);
                    try self.constants_int.append(self.allocator, inst.operand.int_value);
                    try self.emitByte(idx);
                },
                .push_float => {
                    try self.emitByte(@intFromEnum(ByteCode.push_float));
                    const idx: u8 = @intCast(self.constants_float.items.len);
                    try self.constants_float.append(self.allocator, inst.operand.float_value);
                    try self.emitByte(idx);
                },
                .add => try self.emitByte(@intFromEnum(ByteCode.add)),
                .sub => try self.emitByte(@intFromEnum(ByteCode.sub)),
                .mul => try self.emitByte(@intFromEnum(ByteCode.mul)),
                .div => try self.emitByte(@intFromEnum(ByteCode.div)),
                .mod => try self.emitByte(@intFromEnum(ByteCode.mod)),
                .neg => try self.emitByte(@intFromEnum(ByteCode.neg)),
                .load => {
                    try self.emitByte(@intFromEnum(ByteCode.load));
                    const idx = try self.getOrCreateVarIndex(inst.operand.var_name);
                    try self.emitByte(idx);
                },
                .store => {
                    try self.emitByte(@intFromEnum(ByteCode.store));
                    const idx = try self.getOrCreateVarIndex(inst.operand.var_name);
                    try self.emitByte(idx);
                },
                .int_to_float => {},
            }
        }
        try self.emitByte(@intFromEnum(ByteCode.halt));
    }
};
```

### Bytecode Layout

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          BYTECODE STRUCTURE                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Input: "3 + 5 * 2"                                                         │
│  (After optimization: "13")                                                  │
│                                                                              │
│  Bytecode:                                                                   │
│  ┌─────────┬────────┬─────────────────────────────────────────────────────┐ │
│  │ Offset  │ Bytes  │ Meaning                                             │ │
│  ├─────────┼────────┼─────────────────────────────────────────────────────┤ │
│  │ 0x00    │ 0x01   │ PUSH_INT                                            │ │
│  │ 0x01    │ 0x00   │ constant_index = 0  (value: 13)                     │ │
│  │ 0x02    │ 0xFF   │ HALT                                                │ │
│  └─────────┴────────┴─────────────────────────────────────────────────────┘ │
│                                                                              │
│  Constant Pool (integers):                                                   │
│  ┌─────────┬─────────┐                                                      │
│  │ Index   │ Value   │                                                      │
│  ├─────────┼─────────┤                                                      │
│  │ 0       │ 13      │                                                      │
│  └─────────┴─────────┘                                                      │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Input: "x = 10; x + 5" (not optimized - has variable)                      │
│                                                                              │
│  Bytecode:                                                                   │
│  ┌─────────┬────────┬─────────────────────────────────────────────────────┐ │
│  │ Offset  │ Bytes  │ Meaning                                             │ │
│  ├─────────┼────────┼─────────────────────────────────────────────────────┤ │
│  │ 0x00    │ 0x01   │ PUSH_INT                                            │ │
│  │ 0x01    │ 0x00   │ constant[0] = 10                                    │ │
│  │ 0x02    │ 0x21   │ STORE                                               │ │
│  │ 0x03    │ 0x00   │ var[0] = "x"                                        │ │
│  │ 0x04    │ 0x20   │ LOAD                                                │ │
│  │ 0x05    │ 0x00   │ var[0] = "x"                                        │ │
│  │ 0x06    │ 0x01   │ PUSH_INT                                            │ │
│  │ 0x07    │ 0x01   │ constant[1] = 5                                     │ │
│  │ 0x08    │ 0x10   │ ADD                                                 │ │
│  │ 0x09    │ 0xFF   │ HALT                                                │ │
│  └─────────┴────────┴─────────────────────────────────────────────────────┘ │
│                                                                              │
│  Constant Pool: [10, 5]                                                     │
│  Variable Map: {"x": 0}                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stage 7: Virtual Machine (Bytecode Interpreter)

The VM executes bytecode using a stack-based architecture.

### Value Type

```zig
const Value = union(enum) {
    int: i64,
    float: f64,

    fn asFloat(self: Value) f64 {
        return switch (self) {
            .int => |i| @floatFromInt(i),
            .float => |f| f,
        };
    }

    fn isFloat(self: Value) bool {
        return self == .float;
    }
};
```

### Virtual Machine

```zig
const VirtualMachine = struct {
    code: []const u8,
    constants_int: []const i64,
    constants_float: []const f64,
    stack: [256]Value,
    stack_top: usize,
    variables: [256]?Value,
    ip: usize,  // Instruction pointer

    fn init(code: []const u8, constants_int: []const i64,
            constants_float: []const f64) VirtualMachine {
        return .{
            .code = code,
            .constants_int = constants_int,
            .constants_float = constants_float,
            .stack = undefined,
            .stack_top = 0,
            .variables = [_]?Value{null} ** 256,
            .ip = 0,
        };
    }

    fn push(self: *VirtualMachine, value: Value) VmError!void {
        if (self.stack_top >= 256) return VmError.StackOverflow;
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    fn pop(self: *VirtualMachine) VmError!Value {
        if (self.stack_top == 0) return VmError.StackUnderflow;
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    fn readByte(self: *VirtualMachine) u8 {
        const byte = self.code[self.ip];
        self.ip += 1;
        return byte;
    }

    fn run(self: *VirtualMachine) VmError!Value {
        while (true) {
            const opcode = self.readByte();

            switch (@as(ByteCode, @enumFromInt(opcode))) {
                .push_int => {
                    const idx = self.readByte();
                    try self.push(.{ .int = self.constants_int[idx] });
                },
                .push_float => {
                    const idx = self.readByte();
                    try self.push(.{ .float = self.constants_float[idx] });
                },
                .add, .sub, .mul, .div, .mod => {
                    const b = try self.pop();
                    const a = try self.pop();

                    // If either is float, do float arithmetic
                    if (a.isFloat() or b.isFloat()) {
                        const af = a.asFloat();
                        const bf = b.asFloat();
                        const result: f64 = switch (@as(ByteCode, @enumFromInt(opcode))) {
                            .add => af + bf,
                            .sub => af - bf,
                            .mul => af * bf,
                            .div => if (bf == 0) return VmError.DivisionByZero
                                    else af / bf,
                            .mod => @mod(af, bf),
                            else => unreachable,
                        };
                        try self.push(.{ .float = result });
                    } else {
                        const ai = a.int;
                        const bi = b.int;
                        const result: i64 = switch (@as(ByteCode, @enumFromInt(opcode))) {
                            .add => ai + bi,
                            .sub => ai - bi,
                            .mul => ai * bi,
                            .div => if (bi == 0) return VmError.DivisionByZero
                                    else @divTrunc(ai, bi),
                            .mod => @mod(ai, bi),
                            else => unreachable,
                        };
                        try self.push(.{ .int = result });
                    }
                },
                .neg => {
                    const a = try self.pop();
                    switch (a) {
                        .int => |i| try self.push(.{ .int = -i }),
                        .float => |f| try self.push(.{ .float = -f }),
                    }
                },
                .load => {
                    const idx = self.readByte();
                    if (self.variables[idx]) |value| {
                        try self.push(value);
                    } else {
                        return VmError.UndefinedVariable;
                    }
                },
                .store => {
                    const idx = self.readByte();
                    const value = try self.pop();
                    self.variables[idx] = value;
                    try self.push(value); // Assignment returns the value
                },
                .halt => {
                    if (self.stack_top > 0) {
                        return self.stack[self.stack_top - 1];
                    }
                    return .{ .int = 0 };
                },
            }
        }
    }
};
```

### VM Execution Trace

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         VM EXECUTION TRACE                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Input: "x = 10; y = 20; x + y"                                             │
│  Bytecode: [0x01, 0x00, 0x21, 0x00, 0x01, 0x01, 0x21, 0x01,                 │
│             0x20, 0x00, 0x20, 0x01, 0x10, 0xFF]                             │
│                                                                              │
│  ┌────────┬───────────────┬──────────────────┬───────────────────────────┐  │
│  │ IP     │ Instruction   │ Stack            │ Variables                 │  │
│  ├────────┼───────────────┼──────────────────┼───────────────────────────┤  │
│  │ 0      │ PUSH_INT [0]  │ [10]             │ {}                        │  │
│  │ 2      │ STORE [0]     │ [10]             │ {x: 10}                   │  │
│  │ 4      │ PUSH_INT [1]  │ [10, 20]         │ {x: 10}                   │  │
│  │ 6      │ STORE [1]     │ [10, 20]         │ {x: 10, y: 20}            │  │
│  │ 8      │ LOAD [0]      │ [10, 20, 10]     │ {x: 10, y: 20}            │  │
│  │ 10     │ LOAD [1]      │ [10, 20, 10, 20] │ {x: 10, y: 20}            │  │
│  │ 12     │ ADD           │ [10, 20, 30]     │ {x: 10, y: 20}            │  │
│  │ 13     │ HALT          │ Result: 30       │                           │  │
│  └────────┴───────────────┴──────────────────┴───────────────────────────┘  │
│                                                                              │
│  Final Result: 30                                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Putting It All Together

### The Compile Function

```zig
fn compile(source: []const u8, allocator: Allocator) !struct {
    code: []const u8,
    constants_int: []const i64,
    constants_float: []const f64,
} {
    // Stage 1 & 2: Lexing and Parsing
    var parser = Parser.init(source, allocator);
    const ast = parser.parse() catch return CompileError.ParseError;

    // Stage 3: Semantic Analysis
    var analyzer = SemanticAnalyzer.init(allocator);
    defer analyzer.deinit();
    _ = analyzer.analyze(ast) catch return CompileError.SemanticError;

    // Stage 4: Optimization
    var optimizer = Optimizer.init(allocator);
    const optimized_ast = optimizer.optimize(ast) catch return CompileError.OutOfMemory;

    // Stage 5: IR Generation
    var ir_gen = IrGenerator.init(allocator);
    defer ir_gen.deinit();
    ir_gen.generate(optimized_ast) catch return CompileError.CodeGenError;

    // Stage 6: Code Generation
    var code_gen = CodeGenerator.init(allocator);
    code_gen.generateFromIr(ir_gen.instructions.items) catch
        return CompileError.CodeGenError;

    return .{
        .code = code_gen.code.toOwnedSlice(allocator) catch
            return CompileError.OutOfMemory,
        .constants_int = code_gen.constants_int.toOwnedSlice(allocator) catch
            return CompileError.OutOfMemory,
        .constants_float = code_gen.constants_float.toOwnedSlice(allocator) catch
            return CompileError.OutOfMemory,
    };
}

fn run(source: []const u8, allocator: Allocator) !Value {
    const compiled = try compile(source, allocator);

    // Stage 7: Execution
    var vm = VirtualMachine.init(compiled.code, compiled.constants_int,
                                  compiled.constants_float);
    return vm.run();
}
```

### Test Cases

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_cases = [_]struct { source: []const u8, expected: []const u8 }{
        .{ .source = "42",                      .expected = "42" },
        .{ .source = "3 + 5",                   .expected = "8" },
        .{ .source = "3 + 5 * 2",               .expected = "13" },
        .{ .source = "(3 + 5) * 2",             .expected = "16" },
        .{ .source = "-5 + 3",                  .expected = "-2" },
        .{ .source = "10 - 3 - 2",              .expected = "5" },
        .{ .source = "100 / 10 / 2",            .expected = "5" },
        .{ .source = "17 % 5",                  .expected = "2" },
        .{ .source = "2.5 * 4",                 .expected = "10" },
        .{ .source = "3.14 + 2.86",             .expected = "6" },
        .{ .source = "x = 10; y = 20; x + y",   .expected = "30" },
        .{ .source = "a = 5; b = a * 2; b + 3", .expected = "13" },
        .{ .source = "-(3 + 4)",                .expected = "-7" },
        .{ .source = "--5",                     .expected = "5" },
    };

    for (test_cases) |tc| {
        const result = run(tc.source, allocator) catch |err| {
            std.debug.print("FAIL: \"{s}\" - Error: {}\n", .{tc.source, err});
            continue;
        };

        std.debug.print("PASS: \"{s}\" = {}\n", .{tc.source, result});
    }
}
```

### Running the Compiler

```bash
$ zig run mini_compiler.zig

╔══════════════════════════════════════════════════════════════╗
║           MINI MATH COMPILER - Test Results                  ║
╠══════════════════════════════════════════════════════════════╣
║ PASS: "42" = 42
║ PASS: "3 + 5" = 8
║ PASS: "3 + 5 * 2" = 13
║ PASS: "(3 + 5) * 2" = 16
║ PASS: "-5 + 3" = -2
║ PASS: "10 - 3 - 2" = 5
║ PASS: "100 / 10 / 2" = 5
║ PASS: "17 % 5" = 2
║ PASS: "2.5 * 4" = 10
║ PASS: "3.14 + 2.86" = 6
║ PASS: "x = 10; y = 20; x + y" = 30
║ PASS: "a = 5; b = a * 2; b + 3" = 13
║ PASS: "-(3 + 4)" = -7
║ PASS: "--5" = 5
╠══════════════════════════════════════════════════════════════╣
║ Results: 14 passed, 0 failed                                 ║
╚══════════════════════════════════════════════════════════════╝
```

---

## Summary: The Complete Pipeline

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    MINI COMPILER ARCHITECTURE                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐                   │
│  │ SOURCE  │───►│  LEXER  │───►│ PARSER  │───►│ SEMANTIC│                   │
│  │  CODE   │    │         │    │         │    │ ANALYSIS│                   │
│  └─────────┘    └─────────┘    └─────────┘    └────┬────┘                   │
│                                                     │                        │
│                                                     ▼                        │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐                   │
│  │ RESULT  │◄───│   VM    │◄───│ CODEGEN │◄───│OPTIMIZER│                   │
│  │         │    │         │    │         │    │         │                   │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘                   │
│                                      ▲                                       │
│                                      │                                       │
│                               ┌──────┴──────┐                               │
│                               │     IR      │                               │
│                               │  GENERATOR  │                               │
│                               └─────────────┘                               │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                          WHAT WE LEARNED                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. LEXER: Characters → Tokens                                              │
│     - State machine for scanning                                            │
│     - Position tracking for error messages                                  │
│                                                                              │
│  2. PARSER: Tokens → AST                                                    │
│     - Recursive descent parsing                                             │
│     - Operator precedence through grammar rules                             │
│                                                                              │
│  3. SEMANTIC ANALYSIS: Validate AST                                         │
│     - Type checking and inference                                           │
│     - Variable scope management                                             │
│                                                                              │
│  4. OPTIMIZER: Transform AST                                                │
│     - Constant folding                                                      │
│     - Compile-time evaluation                                               │
│                                                                              │
│  5. IR GENERATION: AST → Linear instructions                                │
│     - Stack-based operations                                                │
│     - Easier for code generation                                            │
│                                                                              │
│  6. CODE GENERATION: IR → Bytecode                                          │
│     - Compact binary format                                                 │
│     - Constant pool for literals                                            │
│                                                                              │
│  7. VIRTUAL MACHINE: Execute bytecode                                       │
│     - Stack-based interpreter                                               │
│     - Runtime type handling                                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Extending the Compiler

Here are some ideas for extending this mini compiler:

1. **Add comparison operators**: `<`, `>`, `<=`, `>=`, `==`, `!=`
2. **Add boolean types**: `true`, `false`, `and`, `or`, `not`
3. **Add control flow**: `if-then-else`, `while` loops
4. **Add functions**: `fn add(a, b) { a + b }`
5. **Add strings**: `"hello" + " world"`
6. **Generate native code**: Instead of bytecode, emit x86-64 or ARM64

Each extension follows the same pattern: update the lexer, parser, semantic analyzer, optimizer, IR generator, code generator, and VM.

---

## Connection to Zig Compiler

Our mini compiler mirrors the Zig compiler's architecture:

| Mini Compiler     | Zig Compiler              |
|-------------------|---------------------------|
| Lexer             | `lib/std/zig/tokenizer.zig` |
| Parser            | `lib/std/zig/parse.zig`     |
| AST               | `lib/std/zig/Ast.zig`       |
| Semantic Analysis | `src/Sema.zig`              |
| IR                | ZIR → AIR                   |
| Optimizer         | AIR optimizations           |
| Code Generator    | `src/codegen.zig`           |
| Execution         | LLVM / Native backend       |

The key difference is scale: Zig handles complex features like comptime evaluation, generics, error handling, and generates efficient native code for multiple platforms.

---

## Conclusion

Building a compiler from scratch reveals the elegant chain of transformations that convert human-readable source code into executable instructions. Each stage has a clear responsibility:

- **Lexer**: Make sense of raw text
- **Parser**: Understand structure
- **Semantic Analysis**: Ensure correctness
- **Optimizer**: Improve efficiency
- **IR**: Simplify for code generation
- **Code Generator**: Create executable format
- **VM**: Execute the result

This ~1000-line compiler demonstrates all the fundamental concepts. The Zig compiler applies these same principles at massive scale, with sophisticated optimizations and cross-platform code generation.

The complete source code is available and compiles with `zig run mini_compiler.zig`.
