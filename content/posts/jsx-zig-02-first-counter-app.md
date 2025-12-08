+++
title = "Building UIs in Zig: Part 2 - Your First Counter App"
date = 2024-12-08
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

Let's build a counter - the "Hello World" of UI programming. By the end, you'll have a working app with buttons that increment and decrement a number.

## The Goal

A simple counter with:
- A title
- The current count (colored green for positive, red for negative)
- Plus and minus buttons

## Step 1: The View Function

First, let's describe what we want to see:

```zig
const jsx = @import("jsx");

fn counterView(count: i32) jsx.Node {
    return jsx.col("gap-4 p-6", &.{
        // Title
        jsx.h1("Counter"),

        // The count display
        jsx.text(formatCount(count), "text-4xl font-bold"),

        // Buttons in a row
        jsx.row("gap-4", &.{
            jsx.button("-", "bg-red-500 px-4 py-2 rounded"),
            jsx.button("+", "bg-green-500 px-4 py-2 rounded"),
        }),
    });
}
```

Read it out loud: "A column with gap-4 and padding-6, containing a heading, some text, and a row of buttons."

That's it. No coordinates. No manual positioning.

## Step 2: Understanding the Syntax

Let's break down `jsx.col("gap-4 p-6", &.{...})`:

- `jsx.col` - a vertical column (like CSS `flex-direction: column`)
- `"gap-4 p-6"` - Tailwind-style classes (gap of 16px, padding of 24px)
- `&.{...}` - children elements

The classes work like Tailwind CSS:
- `gap-4` = 16px gap between children
- `p-6` = 24px padding
- `text-4xl` = large text
- `bg-red-500` = red background

## Step 3: Adding State

A counter needs state - the current count:

```zig
pub const CounterApp = struct {
    count: i32 = 0,

    pub fn increment(self: *CounterApp) void {
        self.count += 1;
    }

    pub fn decrement(self: *CounterApp) void {
        self.count -= 1;
    }
};
```

## Step 4: Connecting Buttons to Actions

Buttons need to do something when clicked. We use event handlers:

```zig
const E = enum(usize) { increment, decrement };

const handlers = jsx.handlers(E, .{
    .increment = onIncrement,
    .decrement = onDecrement,
});

// In the view:
jsx.button("-", "bg-red-500").onPress(E.decrement),
jsx.button("+", "bg-green-500").onPress(E.increment),
```

When you click "+", it calls `onIncrement`. Simple.

## Step 5: The Complete App

```zig
const std = @import("std");
const jsx = @import("jsx");

pub const CounterApp = struct {
    count: i32 = 0,
    renderer: jsx.Renderer,
    count_buf: [32]u8 = undefined,

    const E = enum(usize) { increment, decrement };

    const handlers = jsx.handlers(E, .{
        .increment = onIncrement,
        .decrement = onDecrement,
    });

    var instance: ?*CounterApp = null;

    fn onIncrement() void {
        if (instance) |self| self.count += 1;
    }

    fn onDecrement() void {
        if (instance) |self| self.count -= 1;
    }

    pub fn draw(self: *CounterApp) void {
        instance = self;

        const count_str = std.fmt.bufPrint(
            &self.count_buf, "{d}", .{self.count}
        ) catch "?";

        const view = jsx.col("gap-4 p-6", &.{
            jsx.h1("Counter"),
            jsx.text(count_str, "text-4xl font-bold"),
            jsx.row("gap-4", &.{
                jsx.button("-", "bg-red-500 rounded").onPress(E.decrement),
                jsx.button("+", "bg-green-500 rounded").onPress(E.increment),
            }),
        });

        self.renderer.render(view);
        self.renderer.flush();
    }
};
```

## What Just Happened?

1. We described the UI structure declaratively
2. We defined state (`count`)
3. We connected buttons to state changes
4. The framework handles all the rendering

No pixel coordinates. No manual layout. No redraw logic.

## Try It Yourself

1. Add a "Reset" button that sets count to 0
2. Add color - green when positive, red when negative
3. Add a step size selector (increment by 1, 5, or 10)

## What's Next

In Part 3, we'll peek inside the renderer to understand how declarative code becomes pixels on screen.
