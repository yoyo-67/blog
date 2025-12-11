+++
title = "Building UIs in Zig: Part 7 - Your First Counter App"
date = 2025-12-11
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

Let's put everything together and build a complete counter app. By the end, you'll have a working UI with buttons, state, and event handling.

## The Goal

A counter with:
- A title
- The current count (green when positive, red when negative)
- Plus and minus buttons
- A step size selector (1, 5, or 10)
- A reset button

## Step 1: Define State

Every app needs state. Ours tracks a count and step size:

```zig
pub const CounterApp = struct {
    count: i32 = 0,
    step: Step = .one,
    count_buf: [32]u8 = undefined,

    pub const Step = enum(i32) { one = 1, five = 5, ten = 10 };
};
```

## Step 2: Define Events

What can the user do? Define an enum:

```zig
const E = enum(usize) {
    increment,
    decrement,
    reset,
    step_one,
    step_five,
    step_ten,
};
```

## Step 3: Write Handlers

Each event needs a handler function:

```zig
var instance: ?*CounterApp = null;

fn onIncrement() void {
    if (instance) |self| self.count += @intFromEnum(self.step);
}

fn onDecrement() void {
    if (instance) |self| self.count -= @intFromEnum(self.step);
}

fn onReset() void {
    if (instance) |self| self.count = 0;
}

fn onStepOne() void {
    if (instance) |self| self.step = .one;
}

fn onStepFive() void {
    if (instance) |self| self.step = .five;
}

fn onStepTen() void {
    if (instance) |self| self.step = .ten;
}
```

## Step 4: Create the Handler Array

Connect events to handlers:

```zig
const handlers = jsx.handlers(E, .{
    .increment = onIncrement,
    .decrement = onDecrement,
    .reset = onReset,
    .step_one = onStepOne,
    .step_five = onStepFive,
    .step_ten = onStepTen,
});
```

## Step 5: Build the View

Now the fun part - describe the UI:

```zig
pub fn view(self: *CounterApp) jsx.Node {
    // Format count as string
    const count_str = std.fmt.bufPrint(
        &self.count_buf, "{d}", .{self.count}
    ) catch "?";

    return jsx.col("gap-4 p-6 bg-slate-900", &.{
        // Title
        jsx.h1("Counter"),

        // Count display
        jsx.center("flex-1", &.{
            jsx.text(count_str, "text-4xl font-bold")
                .fg(if (self.count >= 0) .green400 else .red400),
        }),

        // Step size selector
        jsx.row("gap-2", &.{
            jsx.toggle("1", "p-2 rounded")
                .active(self.step == .one)
                .onChange(E.step_one),
            jsx.toggle("5", "p-2 rounded")
                .active(self.step == .five)
                .onChange(E.step_five),
            jsx.toggle("10", "p-2 rounded")
                .active(self.step == .ten)
                .onChange(E.step_ten),
        }),

        // Action buttons
        jsx.row("gap-4 justify-center", &.{
            jsx.button("-", "bg-red-500 px-6 py-2 rounded-lg")
                .onPress(E.decrement),
            jsx.button("Reset", "bg-slate-600 px-4 py-2 rounded")
                .onPress(E.reset),
            jsx.button("+", "bg-green-500 px-6 py-2 rounded-lg")
                .onPress(E.increment),
        }),
    });
}
```

## Step 6: The Draw Function

Tie it all together:

```zig
pub fn draw(self: *CounterApp, renderer: *jsx.Renderer) void {
    instance = self;  // Set for handlers

    const ui = self.view();
    renderer.render(ui, &handlers);
}
```

## The Complete App

Here's everything in one place:

```zig
const std = @import("std");
const jsx = @import("jsx");

pub const CounterApp = struct {
    count: i32 = 0,
    step: Step = .one,
    count_buf: [32]u8 = undefined,

    pub const Step = enum(i32) { one = 1, five = 5, ten = 10 };

    const E = enum(usize) {
        increment, decrement, reset,
        step_one, step_five, step_ten,
    };

    const handlers = jsx.handlers(E, .{
        .increment = onIncrement,
        .decrement = onDecrement,
        .reset = onReset,
        .step_one = onStepOne,
        .step_five = onStepFive,
        .step_ten = onStepTen,
    });

    var instance: ?*CounterApp = null;

    fn onIncrement() void {
        if (instance) |self| self.count += @intFromEnum(self.step);
    }
    fn onDecrement() void {
        if (instance) |self| self.count -= @intFromEnum(self.step);
    }
    fn onReset() void {
        if (instance) |self| self.count = 0;
    }
    fn onStepOne() void {
        if (instance) |self| self.step = .one;
    }
    fn onStepFive() void {
        if (instance) |self| self.step = .five;
    }
    fn onStepTen() void {
        if (instance) |self| self.step = .ten;
    }

    pub fn view(self: *CounterApp) jsx.Node {
        const count_str = std.fmt.bufPrint(
            &self.count_buf, "{d}", .{self.count}
        ) catch "?";

        return jsx.col("gap-4 p-6 bg-slate-900", &.{
            jsx.h1("Counter"),

            jsx.center("flex-1", &.{
                jsx.text(count_str, "text-4xl font-bold")
                    .fg(if (self.count >= 0) .green400 else .red400),
            }),

            jsx.row("gap-2", &.{
                jsx.toggle("1", "p-2 rounded")
                    .active(self.step == .one).onChange(E.step_one),
                jsx.toggle("5", "p-2 rounded")
                    .active(self.step == .five).onChange(E.step_five),
                jsx.toggle("10", "p-2 rounded")
                    .active(self.step == .ten).onChange(E.step_ten),
            }),

            jsx.row("gap-4 justify-center", &.{
                jsx.button("-", "bg-red-500 px-6 py-2 rounded-lg")
                    .onPress(E.decrement),
                jsx.button("Reset", "bg-slate-600 px-4 py-2 rounded")
                    .onPress(E.reset),
                jsx.button("+", "bg-green-500 px-6 py-2 rounded-lg")
                    .onPress(E.increment),
            }),
        });
    }

    pub fn draw(self: *CounterApp, renderer: *jsx.Renderer) void {
        instance = self;
        renderer.render(self.view(), &handlers);
    }
};
```

## What Just Happened?

Let's trace a click on "+":

1. **User clicks** on the "+" button
2. **Renderer** checks mouse position, finds it's over the button
3. **Button** has `.onPress(E.increment)` → queues index 0
4. **After rendering**, `flush()` calls `handlers[0]` → `onIncrement()`
5. **Handler** accesses `instance`, increments `count`
6. **Next frame**, `view()` is called with new count
7. **Text shows** updated value

The UI stays in sync because we rebuild it every frame from current state.

## Try It Yourself

1. **Add a "Double" button** that multiplies count by 2
2. **Add a max/min** - don't let count go above 100 or below -100
3. **Add color for the step buttons** - green when active
4. **Add a "Random" button** that sets count to a random number

## What's Next

In Part 8, we'll zoom out and look at the complete architecture - how all the pieces fit together, the module structure, and the key design decisions.
