+++
title = "Building Declarative UI in Zig: Part 1 - The Building Block: Nodes"
date = 2025-12-11
draft = false
series = ["Building Declarative UI in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

Every UI framework needs a way to represent UI elements. In our framework, everything is built from one fundamental type: the **Node**.

## UI as Data

Instead of drawing pixels directly, we represent UI as a tree of data structures. A button isn't "draw a rectangle, then draw text" - it's a struct:

```zig
const button = Node{
    .kind = .button,
    .style = Style{ .bg = .green500, .rounded = .md },
    .props = Props{ .label = "Click me" },
};
```

This is the core idea: **UI elements are just data**.

## The Node Struct

Here's what a Node actually looks like:

```zig
pub const Node = struct {
    kind: Kind,               // What type of element?
    style: Style = .{},       // How does it look?
    props: Props = .{},       // What content/state does it have?
    children: []const Node = &.{},  // What's inside it?
};
```

Four fields. That's it.

## The Kind Enum

The `kind` tells us what type of element this is:

```zig
pub const Kind = enum {
    // Layout containers
    col,      // Vertical stack
    row,      // Horizontal stack
    div,      // Generic container
    center,   // Centers its children

    // Content
    text,     // Text display
    icon,     // Icon display
    spacer,   // Empty space
    divider,  // Horizontal line

    // Interactive
    button,   // Clickable button
    toggle,   // On/off toggle
    input,    // Text input
    slider,   // Value slider
};
```

## The Props Struct

Props hold the element's content and state:

```zig
pub const Props = struct {
    // Content
    label: ?[]const u8 = null,    // Text content
    value: ?[]const u8 = null,    // Secondary text

    // State
    active: bool = false,          // Is it selected/on?
    disabled: bool = false,        // Is it disabled?
    focused: bool = false,         // Does it have focus?

    // Events (handler indices)
    on_press: ?usize = null,       // Click handler
    on_change: ?usize = null,      // Value change handler
};
```

Notice `on_press` is just a `usize` - an index. We'll cover why in Part 5.

## Building a Tree

Nodes contain other nodes. Here's a simple counter UI as a tree:

```
col
├── text "Counter"
└── row
    ├── button "-"
    └── button "+"
```

In code:

```zig
const ui = Node{
    .kind = .col,
    .children = &.{
        Node{ .kind = .text, .props = .{ .label = "Counter" } },
        Node{
            .kind = .row,
            .children = &.{
                Node{ .kind = .button, .props = .{ .label = "-" } },
                Node{ .kind = .button, .props = .{ .label = "+" } },
            },
        },
    },
};
```

## Visual Representation

```
┌─────────────────────────────────────┐
│              Node                   │
├─────────────────────────────────────┤
│  kind: .col                         │
│  style: { gap: 16, p: 24 }         │
│  props: { }                         │
│  children: ─────────────────────────────┐
└─────────────────────────────────────┘   │
         ┌────────────────────────────────┘
         ▼
    ┌─────────┬─────────────────────────┐
    │         │                         │
    ▼         ▼                         │
┌───────────────┐  ┌───────────────┐    │
│     Node      │  │     Node      │    │
├───────────────┤  ├───────────────┤    │
│ kind: .text   │  │ kind: .row    │    │
│ label:"Counter│  │ children: ────────────┐
└───────────────┘  └───────────────┘    │  │
                          ┌─────────────┘  │
                          │ ┌──────────────┘
                          ▼ ▼
                   ┌──────────┬──────────┐
                   │          │          │
                   ▼          ▼
            ┌───────────┐ ┌───────────┐
            │   Node    │ │   Node    │
            ├───────────┤ ├───────────┤
            │kind:.button│kind:.button│
            │ label: "-" │ label: "+" │
            └───────────┘ └───────────┘
```

The `children` field is just a slice - `[]const Node`. No heap allocation, no pointers to manage. The tree lives in static memory.

## Why This Matters

With UI as data:

1. **No hidden state** - Everything is in the struct
2. **Easy to inspect** - Print a node, see everything
3. **Value semantics** - Copy nodes, compare nodes, transform nodes
4. **Comptime friendly** - Build UI at compile time

This is the foundation everything else builds on.

## What's Next

Writing `Node{ .kind = .button, .props = .{ .label = "+" } }` is verbose. In Part 2, we'll create builder functions like `jsx.button("+", "bg-green-500")` that make node creation elegant.

---

*Written by Yohai | Source code: [github.com/yoyo-67/zig-ui](https://github.com/yoyo-67/zig-ui)*
