+++
title = "Building UIs in Zig: Part 1 - Imperative vs Declarative"
date = 2024-12-08
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

When I started building UIs, I wrote code like this:

```zig
// Imperative: step-by-step instructions
fn drawCounter(count: i32) void {
    drawRect(100, 100, 200, 50, GRAY);
    drawText("Counter", 110, 110, 20, WHITE);
    drawRect(100, 160, 200, 80, DARK_GRAY);

    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{count});
    drawText(text, 150, 180, 40, GREEN);

    drawRect(100, 250, 90, 40, RED);
    drawText("-", 140, 260, 30, WHITE);
    drawRect(210, 250, 90, 40, GREEN);
    drawText("+", 250, 260, 30, WHITE);
}
```

This is **imperative** - you tell the computer exactly HOW to draw each pixel.

## The Problem

What happens when requirements change?

- "Move the buttons above the number" - rewrite coordinates
- "Add a reset button" - recalculate all positions
- "Make it responsive" - oh no...

Every change requires manually updating coordinates. It's tedious and error-prone.

## The Declarative Way

Instead, describe WHAT you want:

```zig
fn Counter(count: i32) Node {
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
| You manage state | Framework manages rendering |
| Code = instructions | Code = description |

## The Mental Shift

**Imperative**: "Draw a rectangle at (100, 100), then draw text at (110, 110)..."

**Declarative**: "I want a column with a title, a number, and two buttons"

The framework figures out the rest.

## What's Next

In Part 2, we'll build our first counter app using this declarative approach. You'll see how little code it takes when you stop managing pixels manually.
