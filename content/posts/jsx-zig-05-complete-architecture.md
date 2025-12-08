+++
title = "Building UIs in Zig: Part 5 - The Complete Architecture"
date = 2024-12-08
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial", "architecture"]
+++

We've covered the pieces. Now let's see how they fit together into a complete UI framework.

## The Big Picture

```
┌─────────────────────────────────────────────────┐
│                   Your App                       │
│  State: { count: 5, step: .one }                │
│                    │                             │
│                    ▼                             │
│  View: jsx.col("gap-4", &.{ ... })              │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│               JSX Framework                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ Builder  │  │ Renderer │  │  Events  │      │
│  │ col,row  │  │ Layout+  │  │ Handler  │      │
│  │ text,btn │  │  Draw    │  │ Dispatch │      │
│  └──────────┘  └──────────┘  └──────────┘      │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│                  Raylib                          │
│        drawRect, drawText, getMousePos          │
└─────────────────────────────────────────────────┘
```

## Data Flow

Every frame:

1. **State** - Your app's current data
2. **View** - Function that builds Node tree from state
3. **Render** - Framework calculates layout and draws
4. **Events** - User clicks trigger handlers
5. **Update** - Handlers modify state
6. **Repeat** - Next frame rebuilds view from new state

## The Module Structure

```
jsx/
├── root.zig       # Public API
├── node.zig       # Node struct, modifiers
├── builder.zig    # Element constructors
├── tw.zig         # Comptime Tailwind parser
├── renderer.zig   # Layout and tree walking
├── widgets.zig    # Draw individual nodes
├── layout.zig     # Rect, flex calculations
└── events.zig     # Event queue and dispatch
```

## Key Design Decisions

### 1. Immediate Mode

We rebuild the entire UI every frame. No diffing.

**Why?** Simplicity. No virtual DOM. No reconciliation.

### 2. Comptime Everything

Tailwind classes parsed at compile time. Event enums defined at compile time.

**Why?** Zero runtime cost. Errors caught early.

### 3. Value Types

Nodes are values, not heap allocations:

```zig
pub const Node = struct {
    kind: Kind,
    style: Style,
    children: []const Node,
    props: Props,
};
```

**Why?** No allocator needed. Nodes live on stack or in static memory.

### 4. Explicit Event Binding

Events are indices into a handler array:

```zig
const E = enum(usize) { increment, decrement };

const handlers = jsx.handlers(E, .{
    .increment = onIncrement,
    .decrement = onDecrement,
});

jsx.button("+", "").onPress(E.increment)
```

**Why?** No closures. No heap. Comptime verified.

## Building Components

Create reusable components as functions:

```zig
fn StatBox(label: []const u8, value: []const u8, color: Color) Node {
    return jsx.div("p-4 bg-slate-700 rounded", &.{
        jsx.text(label, "text-sm text-slate-400"),
        jsx.text(value, "text-2xl font-bold").fg(color),
    });
}

// Usage:
jsx.col("gap-4", &.{
    StatBox("Users", "1,234", .green400),
    StatBox("Revenue", "$5,678", .blue400),
});
```

## The Complete Counter App

Here's everything we've learned in one app:

```zig
const std = @import("std");
const jsx = @import("jsx");

pub const CounterApp = struct {
    count: i32 = 0,
    step: Step = .one,
    renderer: jsx.Renderer,
    count_buf: [32]u8 = undefined,

    pub const Step = enum(i32) { one = 1, five = 5, ten = 10 };

    // Events - IDE autocomplete works
    const E = enum(usize) {
        increment, decrement, reset,
        step_one, step_five, step_ten
    };

    // Handlers - named, order-independent, comptime verified
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
        if (instance) |s| s.count += @intFromEnum(s.step);
    }
    fn onDecrement() void {
        if (instance) |s| s.count -= @intFromEnum(s.step);
    }
    fn onReset() void {
        if (instance) |s| s.count = 0;
    }
    fn onStepOne() void {
        if (instance) |s| s.step = .one;
    }
    fn onStepFive() void {
        if (instance) |s| s.step = .five;
    }
    fn onStepTen() void {
        if (instance) |s| s.step = .ten;
    }

    pub fn draw(self: *CounterApp) void {
        instance = self;
        const count_str = std.fmt.bufPrint(
            &self.count_buf, "{d}", .{self.count}
        ) catch "?";

        const view = jsx.col("gap-4 p-6", &.{
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
                jsx.button("-", "bg-red-500 rounded-lg")
                    .onPress(E.decrement),
                jsx.button("Reset", "bg-slate-600 rounded")
                    .onPress(E.reset),
                jsx.button("+", "bg-green-500 rounded-lg")
                    .onPress(E.increment),
            }),
        });

        self.renderer.render(view);
        self.renderer.flush();
    }
};
```

## What You've Learned

1. **Declarative > Imperative** - Describe what, not how
2. **Node trees** - UI as data structures
3. **Comptime parsing** - Zero-cost abstractions
4. **Immediate mode** - Rebuild every frame
5. **Event binding** - Type-safe handler dispatch

## Next Steps

- Add more widgets (slider, checkbox, dropdown)
- Add animations (lerp values over time)
- Add keyboard navigation
- Build a real app!

The foundation is solid. Build on it.

---

*This concludes the "Building UIs in Zig" series. Happy building!*
