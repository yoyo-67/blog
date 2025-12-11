+++
title = "Building UIs in Zig: Part 2 - Building Nodes"
date = 2025-12-11
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

Writing `Node{ .kind = .button, .props = .{ .label = "+" } }` every time is verbose. Let's create builder functions that make node construction elegant.

## The Goal

Transform this:

```zig
const ui = Node{
    .kind = .col,
    .style = Style{ .gap = 16, .p = 24 },
    .children = &.{
        Node{ .kind = .text, .props = .{ .label = "Counter" } },
        Node{ .kind = .button, .props = .{ .label = "+" } },
    },
};
```

Into this:

```zig
const ui = jsx.col("gap-4 p-6", &.{
    jsx.text("Counter", ""),
    jsx.button("+", ""),
});
```

## Builder Functions

Each element type gets a builder function:

```zig
pub fn col(comptime classes: []const u8, children: []const Node) Node {
    return .{
        .kind = .col,
        .style = comptime tw(classes),  // Parse at compile time!
        .children = children,
    };
}

pub fn row(comptime classes: []const u8, children: []const Node) Node {
    return .{
        .kind = .row,
        .style = comptime tw(classes),
        .children = children,
    };
}
```

The `comptime` keyword is key - Tailwind classes like `"gap-4 p-6"` are parsed at compile time. Zero runtime cost. We'll dive deep into the parser in Part 3.

## Text and Buttons

Content elements take a label plus classes:

```zig
pub fn text(label: []const u8, comptime classes: []const u8) Node {
    return .{
        .kind = .text,
        .style = comptime tw(classes),
        .props = .{ .label = label },
    };
}

pub fn button(label: []const u8, comptime classes: []const u8) Node {
    return .{
        .kind = .button,
        .style = comptime tw(classes),
        .props = .{ .label = label },
    };
}

pub fn h1(label: []const u8) Node {
    return .{
        .kind = .text,
        .style = comptime tw("text-3xl font-bold"),
        .props = .{ .label = label },
    };
}
```

Notice `h1` has predefined styles - convenience functions for common patterns.

## Method Chaining

But what about dynamic properties? We can't put runtime values in `comptime` style parsing. The solution: method chaining.

```zig
// This is a Node with a method
pub fn onPress(self: Node, handler: anytype) Node {
    var n = self;
    n.props.on_press = toHandler(handler);
    return n;
}

pub fn fg(self: Node, color: Color) Node {
    var n = self;
    n.style.fg = color;
    return n;
}

pub fn active(self: Node, a: bool) Node {
    var n = self;
    n.props.active = a;
    return n;
}
```

Each method returns a **new Node** with the modified property. This enables chaining:

```zig
jsx.button("+", "bg-green-500")
    .onPress(E.increment)
    .fg(.white)
```

## How Chaining Works

Let's trace through `jsx.button("+", "bg-green-500").onPress(E.increment)`:

```
Step 1: jsx.button("+", "bg-green-500")
┌─────────────────────┐
│ kind: .button       │
│ style: { bg: ... }  │
│ props: {            │
│   label: "+"        │
│   on_press: null    │
│ }                   │
└─────────────────────┘

Step 2: .onPress(E.increment)
┌─────────────────────┐
│ kind: .button       │  ← Same node, copied
│ style: { bg: ... }  │
│ props: {            │
│   label: "+"        │
│   on_press: 0  ◀────── E.increment converted to index
│ }                   │
└─────────────────────┘
```

The `toHandler` function converts enums to indices:

```zig
fn toHandler(handler: anytype) usize {
    const T = @TypeOf(handler);
    if (T == usize) return handler;
    if (@typeInfo(T) == .@"enum") return @intFromEnum(handler);
    @compileError("Handler must be usize or enum");
}
```

## Common Modifiers

Here are the modifiers you'll use most:

```zig
// Event handlers
.onPress(E.action)      // Click handler
.onChange(E.action)     // Value change handler

// Appearance
.fg(.red500)            // Text/foreground color
.bg(.slate800)          // Background color

// State
.active(is_selected)    // Toggle active state
.disabled(is_disabled)  // Disable interaction
```

## Building Complex UI

Now we can build readable UI:

```zig
const view = jsx.col("gap-4 p-6 bg-slate-900", &.{
    jsx.h1("Counter"),

    jsx.text(count_str, "text-4xl font-bold")
        .fg(if (count >= 0) .green400 else .red400),

    jsx.row("gap-4", &.{
        jsx.button("-", "bg-red-500 px-4 py-2 rounded")
            .onPress(E.decrement),
        jsx.button("+", "bg-green-500 px-4 py-2 rounded")
            .onPress(E.increment),
    }),
});
```

Read it out loud: "A column with gap-4, padding-6, and slate-900 background, containing an h1, some text with conditional coloring, and a row of two buttons."

The code reads like a description of the UI.

## Why This Design?

1. **Comptime parsing** - Style strings parsed at compile time
2. **Runtime flexibility** - Method chaining for dynamic values
3. **Value semantics** - Methods return new nodes, no mutation
4. **Type safety** - Wrong arguments = compile error

## What's Next

We glossed over how `tw("gap-4 p-6")` actually works. In Part 3, we'll build the comptime Tailwind parser that turns class strings into Style structs - all at compile time.
