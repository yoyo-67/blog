# Building JSX-like UI in Zig: Part 1 - Introduction and Architecture

*A deep dive into creating declarative, React-inspired UI systems in a systems programming language*

---

## Introduction

If you've ever used React, you know the elegance of JSX:

```jsx
function Counter() {
  const [count, setCount] = useState(0);

  return (
    <Column gap={16} padding={20}>
      <H1>Counter Application</H1>
      <Text size="xl">{count}</Text>
      <Row gap={8}>
        <Button onClick={() => setCount(c => c - 1)}>-</Button>
        <Button onClick={() => setCount(c => c + 1)}>+</Button>
      </Row>
      <Button onClick={() => setCount(0)} variant="secondary">
        Reset
      </Button>
    </Column>
  );
}
```

The code reads like a description of what you want to see. The structure mirrors the visual hierarchy. Changes to state automatically update the UI. It's *declarative*.

But what if you're working in Zig? A language with:
- No macros or preprocessors
- No closures or anonymous functions that capture state
- No garbage collection
- Explicit memory management
- Compile-time metaprogramming instead of runtime reflection

Can we achieve the same declarative elegance?

**Yes, we can.** And in this three-part series, I'll show you exactly how.

By the end, we'll build a counter application that looks like this:

```zig
pub fn render(self: *Counter) void {
    const view = jsx.col(&[_]Node{
        jsx.h1("Counter Application"),

        jsx.text(self.formatCount()).size(.xl),

        jsx.row(&[_]Node{
            jsx.button("-").onPress(DECREMENT),
            jsx.button("+").onPress(INCREMENT),
        }).gap(8),

        jsx.button("Reset").onPress(RESET).color(.secondary),
    }).gap(16).pad(20);

    self.renderer.render(view);
    self.renderer.flush();
}
```

Not quite JSX, but remarkably close for a systems language with no special syntax support.

---

## Why Declarative UI Matters

Before diving into implementation, let's understand why declarative UI is worth pursuing.

### The Imperative Approach

Traditional GUI programming is *imperative*. You tell the computer exactly how to draw each element:

```zig
// Imperative: HOW to draw
fn render(self: *App) void {
    // Draw background
    drawRectangle(0, 0, width, height, DARK_GRAY);

    // Draw title
    drawText("Counter", 20, 20, 32, WHITE);

    // Draw count
    var buf: [32]u8 = undefined;
    const count_str = std.fmt.bufPrint(&buf, "{}", .{self.count}) catch "?";
    drawText(count_str, 20, 70, 48, WHITE);

    // Draw minus button
    const minus_rect = Rectangle{ .x = 20, .y = 130, .w = 60, .h = 40 };
    drawRectangle(minus_rect, if (self.minus_hovered) LIGHT_GRAY else GRAY);
    drawText("-", minus_rect.x + 25, minus_rect.y + 10, 24, WHITE);

    // Draw plus button
    const plus_rect = Rectangle{ .x = 90, .y = 130, .w = 60, .h = 40 };
    drawRectangle(plus_rect, if (self.plus_hovered) LIGHT_GRAY else GRAY);
    drawText("+", plus_rect.x + 25, plus_rect.y + 10, 24, WHITE);

    // ... more drawing code ...
}
```

Problems with this approach:
1. **Hard to read**: The visual structure is buried in coordinate math
2. **Hard to maintain**: Moving one element means updating coordinates for everything below
3. **Hard to refactor**: Extracting a "button" component requires manual wiring
4. **Error-prone**: Easy to forget to update hover state or click handling

### The Declarative Approach

Declarative UI inverts the model. You describe *what* you want, and the framework figures out *how*:

```zig
// Declarative: WHAT to show
fn render(self: *App) void {
    const view = jsx.col(&[_]Node{
        jsx.h1("Counter"),
        jsx.text(self.formatCount()).size(.xl),
        jsx.row(&[_]Node{
            jsx.button("-").onPress(DECREMENT),
            jsx.button("+").onPress(INCREMENT),
        }).gap(8),
    }).gap(16).pad(20);

    self.renderer.render(view);
}
```

Benefits:
1. **Readable**: Structure matches visual hierarchy
2. **Maintainable**: Layout is automatic - add/remove elements freely
3. **Composable**: Components are just functions returning nodes
4. **Self-documenting**: The code describes the UI

---

## The Architecture

Our JSX-like system has four layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                         │
│                                                              │
│   Your code: Counter, TodoList, Settings, etc.              │
│   Uses the builder functions to create UI trees              │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    BUILDER LAYER                             │
│                                                              │
│   jsx.col(), jsx.row(), jsx.button(), jsx.text()            │
│   Returns Node structs with sensible defaults                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      NODE LAYER                              │
│                                                              │
│   Node struct: { kind, props, children }                    │
│   Immutable value type with modifier methods                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    RENDERER LAYER                            │
│                                                              │
│   Traverses node tree, calculates layout, draws pixels      │
│   Handles input, queues events, calls handlers               │
└─────────────────────────────────────────────────────────────┘
```

Let's explore each layer in detail.

---

## Layer 1: The Node - Our Virtual DOM Element

At the heart of our system is the `Node` type. Think of it as React's virtual DOM element - a lightweight description of what to render.

### The Node Structure

```zig
// packages/jsx/src/node.zig

pub const Node = struct {
    /// What kind of element is this?
    kind: Kind,

    /// Properties that control appearance and behavior
    props: Props = .{},

    /// Child nodes (for containers like col, row, list)
    children: []const Node = &.{},
};
```

Three fields. That's it. But these three fields can describe any UI:

- **kind**: Is this a button? A text label? A column layout?
- **props**: What color? What size? What handler to call on click?
- **children**: What nodes are inside this one?

### Node Kinds

We define an enum of all possible node types:

```zig
pub const Kind = enum {
    // ─────────────────────────────────────────────────
    // Layout Nodes
    // These control how children are positioned
    // ─────────────────────────────────────────────────

    col,        // Vertical stack (like CSS flexbox column)
                // Children are arranged top-to-bottom

    row,        // Horizontal stack (like CSS flexbox row)
                // Children are arranged left-to-right

    center,     // Centers its child in available space
                // Useful for modals, splash screens

    stack,      // Z-axis stacking (children overlap)
                // Last child is on top

    scroll,     // Scrollable container
                // Shows scrollbar when content overflows

    // ─────────────────────────────────────────────────
    // Content Nodes
    // These display information
    // ─────────────────────────────────────────────────

    text,       // Text label
                // Props: label, size, color, weight

    icon,       // Icon display
                // Props: icon (name), size, color

    spacer,     // Flexible empty space
                // Expands to fill available room

    divider,    // Horizontal line separator
                // Visual break between sections

    // ─────────────────────────────────────────────────
    // Interactive Nodes
    // These respond to user input
    // ─────────────────────────────────────────────────

    button,     // Clickable button
                // Props: label, on_press, disabled

    toggle,     // On/off switch
                // Props: label, active, on_change

    input,      // Text input field
                // Props: value, placeholder, on_change

    slider,     // Value slider
                // Props: value, min, max, on_change

    // ─────────────────────────────────────────────────
    // Container Nodes
    // These group and style content
    // ─────────────────────────────────────────────────

    card,       // Styled container with background/border
                // Props: padding, radius, bg, border

    list,       // Scrollable list of items
                // Optimized for many children

    item,       // Single list item
                // Props: selected, on_press

    modal,      // Overlay dialog
                // Renders above other content
};
```

Each kind has specific rendering logic. A `col` arranges children vertically. A `button` draws a clickable rectangle. A `text` renders a string.

### Node Properties

The `Props` struct holds every possible property. Most are optional with sensible defaults:

```zig
pub const Props = struct {
    // ─────────────────────────────────────────────────
    // Content Properties
    // ─────────────────────────────────────────────────

    /// Text content for text, button, toggle nodes
    label: ?[]const u8 = null,

    /// Icon name for icon nodes
    icon: ?[]const u8 = null,

    /// Current value for input, slider nodes
    value: ?[]const u8 = null,

    // ─────────────────────────────────────────────────
    // Layout Properties
    // ─────────────────────────────────────────────────

    /// Space between children (for col, row)
    gap: i32 = 0,

    /// Internal padding
    pad: i32 = 0,

    /// Flex grow factor (0 = fixed size, >0 = flexible)
    /// Higher values = more space relative to siblings
    flex: i32 = 0,

    /// Fixed dimensions (null = auto-size)
    w: ?i32 = null,
    h: ?i32 = null,

    /// Dimension constraints
    min_w: ?i32 = null,
    min_h: ?i32 = null,
    max_w: ?i32 = null,
    max_h: ?i32 = null,

    // ─────────────────────────────────────────────────
    // Style Properties
    // ─────────────────────────────────────────────────

    /// Text size
    size: Size = .md,

    /// Font weight
    weight: Weight = .normal,

    /// Foreground color (text, icons)
    color: ?Color = null,

    /// Background color
    bg: ?Color = null,

    /// Border color
    border: ?Color = null,

    /// Corner radius for rounded rectangles
    radius: i32 = 0,

    // ─────────────────────────────────────────────────
    // State Properties
    // ─────────────────────────────────────────────────

    /// Toggle/checkbox active state
    active: bool = false,

    /// Disabled state (no interaction)
    disabled: bool = false,

    /// Selected state (for list items)
    selected: bool = false,

    /// Focus state (for inputs)
    focused: bool = false,

    /// Hover state (usually set by renderer)
    hovered: bool = false,

    // ─────────────────────────────────────────────────
    // Event Properties
    // ─────────────────────────────────────────────────

    /// Handler index for press/click events
    on_press: ?usize = null,

    /// Handler index for value change events
    on_change: ?usize = null,

    /// Handler index for focus events
    on_focus: ?usize = null,

    /// Handler index for blur events
    on_blur: ?usize = null,

    // ─────────────────────────────────────────────────
    // Custom Data
    // ─────────────────────────────────────────────────

    /// User data pointer (for custom components)
    data: ?*anyopaque = null,
};
```

**Why one big Props struct instead of per-kind props?**

Simplicity. In Zig, we can't easily have type-safe per-kind props without either:
- Complex tagged unions (verbose)
- Comptime type generation (complex)

A single Props struct with optional fields is simpler and the unused fields cost nothing at runtime (they're just null/zero).

### The Size and Color Enums

```zig
pub const Size = enum {
    xs,     // Extra small (11px)
    sm,     // Small (13px)
    md,     // Medium (15px) - default
    lg,     // Large (18px)
    xl,     // Extra large (24px)
    xxl,    // Title size (32px)
};

pub const Weight = enum {
    normal,     // Regular weight
    medium,     // Semi-bold
    bold,       // Bold
};

pub const Color = enum {
    // Semantic colors
    primary,        // Main text color
    secondary,      // Secondary text
    muted,          // Subtle text (hints, captions)
    accent,         // Brand/highlight color
    success,        // Success states (green)
    warning,        // Warning states (yellow)
    danger,         // Error/destructive (red)

    // Surface colors
    bg,             // Primary background
    bg_secondary,   // Secondary background (cards)
    border,         // Border color

    // Absolute colors
    white,
    black,
};
```

Using semantic colors instead of RGB values means:
1. Easy theming (change colors in one place)
2. Consistent UI (can't accidentally use wrong shade)
3. Accessible (semantic names encourage proper contrast)

---

## The Modifier Pattern

Here's where Zig's value semantics shine. We implement a **fluent modifier API**:

```zig
// Each modifier returns a NEW node with the property changed
pub fn gap(self: Node, g: i32) Node {
    var n = self;      // Copy the node (cheap - it's just a struct)
    n.props.gap = g;   // Modify the copy
    return n;          // Return the modified copy
}

pub fn pad(self: Node, p: i32) Node {
    var n = self;
    n.props.pad = p;
    return n;
}

pub fn flex(self: Node, f: i32) Node {
    var n = self;
    n.props.flex = f;
    return n;
}

pub fn size(self: Node, s: Size) Node {
    var n = self;
    n.props.size = s;
    return n;
}

pub fn color(self: Node, c: Color) Node {
    var n = self;
    n.props.color = c;
    return n;
}

pub fn active(self: Node, a: bool) Node {
    var n = self;
    n.props.active = a;
    return n;
}

pub fn disabled(self: Node, d: bool) Node {
    var n = self;
    n.props.disabled = d;
    return n;
}

pub fn onPress(self: Node, handler: usize) Node {
    var n = self;
    n.props.on_press = handler;
    return n;
}

pub fn onChange(self: Node, handler: usize) Node {
    var n = self;
    n.props.on_change = handler;
    return n;
}
```

This enables the fluent chaining syntax:

```zig
// Start with a button, chain modifiers
jsx.button("Submit")
    .onPress(0)           // Returns new Node with on_press = 0
    .disabled(false)      // Returns new Node with disabled = false
    .color(.accent)       // Returns new Node with color = .accent
```

Each call returns a new `Node`. Since `Node` is a small struct (just three fields), copying is essentially free.

**Why not mutate in place?**

Immutability makes reasoning easier:
- No aliasing surprises
- Safe to pass nodes around
- Comptime evaluation works naturally

---

## Layer 2: The Builder - JSX-like Constructors

The builder layer provides ergonomic functions to create nodes:

```zig
// packages/jsx/src/builder.zig

const Node = @import("node.zig").Node;

/// Vertical stack - children arranged top to bottom
/// Default gap: 8px
pub fn col(children: []const Node) Node {
    return .{
        .kind = .col,
        .props = .{ .gap = 8 },
        .children = children,
    };
}

/// Horizontal stack - children arranged left to right
/// Default gap: 8px
pub fn row(children: []const Node) Node {
    return .{
        .kind = .row,
        .props = .{ .gap = 8 },
        .children = children,
    };
}

/// Text display
pub fn text(label: []const u8) Node {
    return .{
        .kind = .text,
        .props = .{ .label = label },
    };
}

/// Large heading (like HTML <h1>)
pub fn h1(label: []const u8) Node {
    return .{
        .kind = .text,
        .props = .{
            .label = label,
            .size = .xxl,
            .weight = .bold,
        },
    };
}

/// Muted text (captions, hints)
pub fn muted(label: []const u8) Node {
    return .{
        .kind = .text,
        .props = .{
            .label = label,
            .color = .muted,
            .size = .sm,
        },
    };
}

/// Clickable button
pub fn button(label: []const u8) Node {
    return .{
        .kind = .button,
        .props = .{ .label = label },
    };
}

/// Flexible spacer - expands to fill available space
pub fn spacer() Node {
    return .{
        .kind = .spacer,
        .props = .{ .flex = 1 },
    };
}

/// Horizontal divider line
pub fn divider() Node {
    return .{ .kind = .divider };
}
```

These functions provide:
1. **Sensible defaults**: `col` has gap=8 by default
2. **Semantic shortcuts**: `h1` sets size=xxl and weight=bold
3. **Clean API**: `jsx.button("Click")` instead of `Node{ .kind = .button, .props = .{ .label = "Click" } }`

---

## Counter Example: The UI Tree

Let's see how our counter app's UI tree looks:

```zig
const view = jsx.col(&[_]Node{
    jsx.h1("Counter"),
    jsx.text(self.formatCount()).size(.xl),
    jsx.row(&[_]Node{
        jsx.button("-").onPress(DECREMENT),
        jsx.button("+").onPress(INCREMENT),
    }).gap(8),
    jsx.button("Reset").onPress(RESET),
}).gap(16).pad(20);
```

This creates the following tree structure:

```
col { gap: 16, pad: 20 }
├── text { label: "Counter", size: xxl, weight: bold }
├── text { label: "42", size: xl }
├── row { gap: 8 }
│   ├── button { label: "-", on_press: 0 }
│   └── button { label: "+", on_press: 1 }
└── button { label: "Reset", on_press: 2 }
```

The renderer will traverse this tree, calculate positions, and draw each node.

---

## Summary

In Part 1, we've established:

1. **Why declarative UI matters**: Readable, maintainable, composable code
2. **The architecture**: Four layers from application to renderer
3. **The Node type**: Our virtual DOM element with kind, props, children
4. **The modifier pattern**: Fluent API via immutable transformations
5. **The builder layer**: Ergonomic constructors with sensible defaults

In **Part 2**, we'll implement the **Renderer** - the engine that turns our node tree into actual pixels on screen. We'll cover:
- Layout algorithms (flexbox-like column and row)
- Drawing text, buttons, and other elements
- Hit testing for mouse interaction
- The theme system for consistent styling

In **Part 3**, we'll tackle the **Event System** - how to handle user interaction without closures:
- The handler array pattern
- Event queuing during render
- State management strategies
- Building the complete counter application

---

*Next: [Part 2 - The Renderer and Layout System](./02-renderer-and-layout.md)*
