+++
title = "Building Declarative UI in Zig: Part 6 - Imperative vs Declarative"
date = 2025-12-11
draft = false
series = ["Building Declarative UI in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

Now that you understand how the framework works - nodes, builders, styles, rendering, events - let's step back and see WHY this approach is valuable.

## The Imperative Approach

Without a framework, you write UI like this:

```zig
fn drawCounter(count: i32) void {
    // Draw container
    drawRect(100, 100, 200, 200, DARK_GRAY);

    // Draw title
    drawText("Counter", 110, 110, 20, WHITE);

    // Draw count
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{count});
    drawText(text, 150, 150, 40, GREEN);

    // Draw minus button
    drawRect(110, 200, 80, 40, RED);
    drawText("-", 145, 210, 30, WHITE);

    // Draw plus button
    drawRect(210, 200, 80, 40, GREEN);
    drawText("+", 245, 210, 30, WHITE);
}
```

This is **imperative** - you tell the computer exactly HOW to draw each pixel.

## The Problem

What happens when requirements change?

**"Move the buttons above the number"**
- Recalculate Y coordinates for buttons
- Recalculate Y coordinate for number
- Hope you didn't miss anything

**"Add a reset button"**
- Calculate X position for three buttons
- Adjust width of existing buttons
- Update all X coordinates

**"Make it responsive"**
- Oh no...

Every change requires manually updating coordinates. It's tedious, error-prone, and doesn't scale.

## The Declarative Approach

With our framework, describe WHAT you want:

```zig
fn counterView(count: i32) Node {
    return jsx.col("gap-4 p-6", &.{
        jsx.h1("Counter"),
        jsx.text(count_str, "text-4xl text-green-500"),
        jsx.row("gap-4", &.{
            jsx.button("-", "bg-red-500"),
            jsx.button("+", "bg-green-500"),
        }),
    });
}
```

This is **declarative** - you describe the structure, not the pixels.

## Why Declarative Wins

| Imperative | Declarative |
|------------|-------------|
| Manual coordinates | Automatic layout |
| Hard to change | Easy to restructure |
| You manage rendering | Framework manages rendering |
| Code = instructions | Code = description |

**"Move the buttons above the number"**
```zig
jsx.col("gap-4 p-6", &.{
    jsx.h1("Counter"),
    jsx.row("gap-4", &.{           // ← Moved up
        jsx.button("-", "bg-red-500"),
        jsx.button("+", "bg-green-500"),
    }),
    jsx.text(count_str, "text-4xl"),  // ← Moved down
});
```

Just reorder the lines. Layout recalculates automatically.

**"Add a reset button"**
```zig
jsx.row("gap-4", &.{
    jsx.button("-", "bg-red-500"),
    jsx.button("Reset", "bg-slate-500"),  // ← Added
    jsx.button("+", "bg-green-500"),
});
```

Add one line. The row handles spacing.

**"Make it responsive"**

The framework handles it. Containers fill available space, flex items expand.

## The Mental Shift

**Imperative thinking**:
"Draw a rectangle at (100, 100) with size (200, 50), then draw text at (110, 110)..."

**Declarative thinking**:
"I want a column with a title, a number, and two buttons in a row"

You describe the **what**, the framework figures out the **how**.

## Now You Understand

After learning about:
- **Nodes** - UI as data structures
- **Builders** - Convenient node construction
- **Styles** - Comptime Tailwind parsing
- **Rendering** - Tree walking and layout
- **Events** - Index-based handlers

You can see what the framework does for you:

1. **Nodes** let you describe structure instead of pixels
2. **Builders** make that description readable
3. **Styles** give you expressive layout without runtime cost
4. **Rendering** handles all the coordinate math
5. **Events** connect interactions to your code

The framework is the bridge between "what you want" and "pixels on screen".

## The Tradeoff

Declarative isn't free:
- You learn the framework's API
- Some things are harder to express
- Debugging can be indirect

But for most UI work, the benefits far outweigh the costs. Especially as UIs grow larger and more complex.

## What's Next

Time to put it all together. In Part 7, we'll build a complete counter app from scratch, step by step, using everything we've learned.

---

*Written by Yohai | Source code: [github.com/yoyo-67/zig-ui](https://github.com/yoyo-67/zig-ui)*
