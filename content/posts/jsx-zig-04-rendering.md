+++
title = "Building Declarative UI in Zig: Part 4 - Rendering: From Tree to Pixels"
date = 2025-12-11
draft = false
series = ["Building Declarative UI in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

We have nodes, builders, and styles. Now let's turn that tree of data into actual pixels on screen.

## The Render Loop

Every frame, the renderer does three things:

```zig
pub fn render(self: *Renderer, root: Node) void {
    // 1. Clear screen
    rl.clearBackground(DEFAULT_BG);

    // 2. Walk the tree, calculate layout, draw
    self.renderNode(root, self.bounds);

    // 3. Handle any triggered events
    self.events.flush();
}
```

## Dispatching by Kind

The core of rendering is a switch on `node.kind`:

```zig
fn renderNode(self: *Renderer, node: Node, bounds: Rect) void {
    switch (node.kind) {
        .col => self.renderCol(node, bounds),
        .row => self.renderRow(node, bounds),
        .text => renderText(node, bounds),
        .button => self.renderButton(node, bounds),
        .toggle => self.renderToggle(node, bounds),
        // ... etc
    }
}
```

Visual flow:

```
                    renderNode(node, bounds)
                            │
                            ▼
               ┌────────────────────────┐
               │   switch (node.kind)   │
               └────────────────────────┘
                            │
        ┌───────────┬───────┴───────┬───────────┐
        ▼           ▼               ▼           ▼
     .col        .row           .button      .text
        │           │               │           │
        ▼           ▼               ▼           ▼
  renderCol    renderRow      renderButton  renderText
        │           │               │           │
        ▼           ▼               │           │
   [recurse     [recurse           │           │
    children]    children]          ▼           ▼
                              [draw rect]  [draw text]
                              [draw label]
                              [check click]
```

Layout nodes recurse into children. Leaf nodes just draw.

## Column Layout

Here's how `renderCol` stacks children vertically:

```zig
fn renderCol(self: *Renderer, node: Node, bounds: Rect) void {
    // Calculate content area (inside padding)
    const content = Rect{
        .x = bounds.x + node.style.getPadLeft(),
        .y = bounds.y + node.style.getPadTop(),
        .w = bounds.w - node.style.getPadLeft() - node.style.getPadRight(),
        .h = bounds.h - node.style.getPadTop() - node.style.getPadBottom(),
    };

    var y = content.y;
    const gap = node.style.gap;

    for (node.children) |child| {
        const child_h = measureHeight(child);

        self.renderNode(child, Rect{
            .x = content.x,
            .y = y,
            .w = content.w,
            .h = child_h,
        });

        y += child_h + gap;
    }
}
```

Visual:

```
Container bounds
┌──────────────────────────────────────┐
│ padding-top                          │
│  ┌────────────────────────────────┐  │
│  │         Child 1                │  │
│  │         (height)               │  │
│  └────────────────────────────────┘  │
│                                      │
│            ◀── gap ──▶               │
│                                      │
│  ┌────────────────────────────────┐  │
│  │         Child 2                │  │
│  │         (height)               │  │
│  └────────────────────────────────┘  │
│ padding-bottom                       │
└──────────────────────────────────────┘
```

Row layout is the same idea, but horizontal.

## Flex Layout

What about `flex-1`? Flex children expand to fill available space.

```zig
jsx.col("", &.{
    jsx.text("Header", ""),           // Fixed height
    jsx.div("flex-1", &.{...}),       // Takes remaining space
    jsx.text("Footer", ""),           // Fixed height
})
```

The calculation:

```zig
fn calcFlexSizes(children: []const Node, available: i32, gap: i32) FlexCalc {
    var fixed_total: i32 = 0;
    var flex_total: i32 = 0;

    // Sum up fixed sizes and flex values
    for (children) |child| {
        if (child.style.flex > 0) {
            flex_total += child.style.flex;
        } else {
            fixed_total += measureHeight(child);
        }
    }

    // Space left after fixed children and gaps
    const gaps = @intCast(i32, children.len - 1) * gap;
    const remaining = available - fixed_total - gaps;

    // Each flex unit gets this many pixels
    const flex_unit = if (flex_total > 0)
        @divFloor(remaining, flex_total)
    else
        0;

    return .{ .flex_unit = flex_unit };
}
```

Example with 300px available, 10px gaps:

```
Available: 300px
┌──────────────────────────────────────────────────────────┐
│                                                          │
└──────────────────────────────────────────────────────────┘

Children: Fixed (50px), flex-1, flex-2

Step 1: Subtract fixed + gaps
┌────────┐     ┌─────────────────────────────────────────┐
│ Fixed  │ gap │           Remaining: 230px              │
│  50px  │10px │                                         │
└────────┘     └─────────────────────────────────────────┘

Step 2: Divide remaining by total flex (1+2=3)
         flex_unit = 230 / 3 = 76px

Step 3: Assign to flex children
┌────────┐     ┌──────────────┐     ┌────────────────────────────┐
│ Fixed  │ gap │   flex-1     │ gap │         flex-2             │
│  50px  │10px │  1×76=76px   │10px │       2×76=152px           │
└────────┘     └──────────────┘     └────────────────────────────┘
```

## Measuring Height

How do we know a button is 36px tall? The `measureHeight` function:

```zig
fn measureHeight(node: Node) i32 {
    // Explicit height wins
    if (node.style.h) |h| return h;

    switch (node.kind) {
        .col => {
            // Sum of children + gaps + padding
            var total: i32 = 0;
            for (node.children) |child| {
                total += measureHeight(child);
            }
            const gaps = (node.children.len - 1) * node.style.gap;
            const pad = node.style.getPadTop() + node.style.getPadBottom();
            return total + gaps + pad;
        },
        .row => {
            // Max of children + padding
            var max_h: i32 = 0;
            for (node.children) |child| {
                const h = measureHeight(child);
                if (h > max_h) max_h = h;
            }
            return max_h + node.style.getPadTop() + node.style.getPadBottom();
        },
        .text => return 22,  // Base text height
        .button, .toggle => return 36,  // Widget height
        else => return 32,
    }
}
```

## Drawing a Button

Here's how a button actually gets drawn:

```zig
fn renderButton(self: *Renderer, node: Node, bounds: Rect) void {
    const hover = isHovered(bounds);
    const press = hover and rl.isMouseButtonDown(.left);

    // Background color based on state
    const bg = if (node.props.disabled)
        DISABLED_BG
    else if (press)
        ACTIVE_BG
    else if (hover)
        HOVER_BG
    else
        node.style.bg orelse DEFAULT_BG;

    // Draw rounded rectangle
    const radius = node.style.getBorderRadius();
    rl.drawRectangleRounded(bounds.toRaylib(), radius, 8, bg);

    // Draw label centered
    if (node.props.label) |label| {
        const font_size = node.style.getFontSize();
        const text_w = rl.measureText(label, font_size);
        const tx = bounds.x + @divFloor(bounds.w - text_w, 2);
        const ty = bounds.y + @divFloor(bounds.h - font_size, 2);
        rl.drawText(label, tx, ty, font_size, TEXT_COLOR);
    }

    // Check for click and queue event
    if (!node.props.disabled and hover and rl.isMouseButtonPressed(.left)) {
        if (node.props.on_press) |handler_idx| {
            self.events.queue(handler_idx);
        }
    }
}
```

Three responsibilities:
1. **Draw background** with hover/press states
2. **Draw label** centered in bounds
3. **Detect clicks** and queue events

## The Full Picture

When you write:

```zig
const view = jsx.col("gap-4 p-6", &.{
    jsx.text("Hello", "text-2xl"),
    jsx.button("+", "bg-green-500"),
});
renderer.render(view);
```

1. `jsx.col` creates a Node with parsed style and children
2. `jsx.text` and `jsx.button` create child Nodes
3. `render()` clears screen
4. `renderNode` dispatches to `renderCol`
5. `renderCol` calculates layout for each child
6. Children are rendered recursively
7. Button checks for clicks, queues handlers
8. `flush()` calls queued handlers

## What's Next

We saw that buttons "queue" events. But how does that work? In Part 5, we'll build the event system that connects UI interactions to your code.

---

*Written by Yohai | Source code: [github.com/yoyo-67/zig-ui](https://github.com/yoyo-67/zig-ui)*
