+++
title = "Building UIs in Zig: Part 3 - How the Renderer Works"
date = 2024-12-08
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

You've built a counter app. But how does `jsx.col("gap-4", &.{...})` become pixels? Let's peek behind the curtain.

## The Node Tree

When you write:

```zig
jsx.col("gap-4 p-6", &.{
    jsx.h1("Counter"),
    jsx.button("+", "bg-green-500"),
})
```

You're creating a **tree of nodes**:

```
col (gap-4, p-6)
├── text "Counter" (text-3xl, font-bold)
└── button "+" (bg-green-500)
```

Each node is a simple struct:

```zig
pub const Node = struct {
    kind: Kind,           // col, row, text, button...
    style: Style,         // parsed from Tailwind classes
    children: []const Node,
    props: Props,         // label, event handlers, etc.
};
```

## Step 1: Parse Tailwind Classes (Comptime)

The magic starts at compile time. When you write `"gap-4 p-6"`, it's parsed into a `Style` struct:

```zig
// This happens at COMPILE TIME
const style = tw("gap-4 p-6");
// Results in:
// Style{ .gap = 16, .p = 24 }
```

No runtime string parsing. Zero cost.

## Step 2: Layout Calculation

The renderer walks the tree and calculates bounds for each node:

```zig
fn renderCol(node: Node, bounds: Rect) void {
    var y = bounds.y + node.style.padding;

    for (node.children) |child| {
        const child_height = measureHeight(child);
        renderNode(child, Rect{
            .x = bounds.x + node.style.padding,
            .y = y,
            .w = bounds.w - node.style.padding * 2,
            .h = child_height,
        });
        y += child_height + node.style.gap;
    }
}
```

**Column layout**: Stack children vertically, add gap between them.

**Row layout**: Same idea, but horizontally.

## Step 3: Drawing

Once we know where everything goes, drawing is simple:

```zig
fn renderButton(node: Node, bounds: Rect) void {
    // Draw background
    if (node.style.bg) |color| {
        drawRect(bounds, color);
    }

    // Draw text centered
    const label = node.props.label;
    drawTextCentered(label, bounds, node.style.text_color);
}
```

## The Render Loop

Every frame:

```zig
pub fn render(self: *Renderer, root: Node) void {
    // 1. Clear screen
    clearBackground(DARK_GRAY);

    // 2. Walk the tree, calculate layout, draw
    self.renderNode(root, self.bounds);

    // 3. Handle any triggered events
    self.events.flush();
}
```

## Flex Layout

For flexible sizing, we use flex values:

```zig
jsx.col("", &.{
    jsx.text("Header", ""),           // Fixed height
    jsx.div("flex-1", &.{...}),       // Takes remaining space
    jsx.text("Footer", ""),           // Fixed height
})
```

The renderer:
1. Measures fixed-size children
2. Divides remaining space among flex children
3. Positions everything

## Event Handling

When you click a button:

1. Renderer checks mouse position against button bounds
2. If hit, queues the event ID
3. After rendering, `flush()` calls the handler

```zig
fn renderButton(ctx: *RenderCtx, node: Node, bounds: Rect) void {
    // Draw button...

    // Check for click
    if (isMouseInRect(bounds) and isMousePressed()) {
        if (node.props.on_press) |handler_id| {
            ctx.events.queue(handler_id);
        }
    }
}
```

## Why This Architecture?

1. **Immediate mode**: Rebuild UI every frame. No diffing, no virtual DOM.
2. **Comptime parsing**: Tailwind classes parsed at compile time. Zero runtime cost.
3. **Simple tree**: Just structs and slices. No allocations during rendering.
4. **Decoupled**: View code doesn't know about pixels. Renderer doesn't know about app logic.

## What's Next

In Part 4, we'll build the Tailwind parser that makes `"gap-4 p-6"` work at compile time.
