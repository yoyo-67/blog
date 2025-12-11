+++
title = "Building UIs in Zig: Part 3 - Styling: The Comptime Tailwind Parser"
date = 2025-12-11
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial", "comptime"]
+++

The magic of `jsx.col("gap-4 p-6 bg-slate-800", &.{...})` is that those strings are parsed at **compile time**. No runtime cost. Let's build it.

## The Goal

Turn this:
```zig
const style = tw("gap-4 p-6 bg-slate-800 rounded-lg");
```

Into this (at compile time):
```zig
Style{
    .gap = 16,
    .p = 24,
    .bg = Color.slate800,
    .rounded = .lg,
}
```

## The Style Struct

First, define what styles we support:

```zig
pub const Style = struct {
    // Spacing
    gap: i32 = 0,
    p: i32 = 0,      // padding (all sides)
    px: ?i32 = null, // padding horizontal
    py: ?i32 = null, // padding vertical

    // Flex
    flex: i32 = 0,
    flex_dir: FlexDir = .col,

    // Appearance
    bg: ?Color = null,
    fg: ?Color = null,
    rounded: Rounded = .none,

    // Text
    font_size: i32 = 16,
    font_weight: FontWeight = .normal,
};
```

Why `?i32` for directional spacing? So we can tell "not set" from "explicitly zero". The getters cascade:

```zig
pub fn getPadLeft(self: Style) i32 {
    return self.px orelse self.p;
}
```

`px-4` overrides `p-2`.

## The Parser

Comptime string parsing in Zig is surprisingly clean:

```zig
pub fn tw(comptime classes: []const u8) Style {
    var style = Style{};

    // Split by spaces and parse each class
    var iter = std.mem.splitScalar(u8, classes, ' ');
    while (iter.next()) |class| {
        if (class.len == 0) continue;
        parseClass(&style, class);
    }

    return style;
}
```

## Parsing Individual Classes

Each class follows patterns:

```zig
fn parseClass(style: *Style, class: []const u8) void {
    // Gap: gap-1, gap-2, gap-4, etc.
    if (startsWith(class, "gap-")) {
        style.gap = parseSpacing(class[4..]);
        return;
    }

    // Padding: p-1, px-2, py-4, etc.
    if (startsWith(class, "p-")) {
        style.p = parseSpacing(class[2..]);
        return;
    }
    if (startsWith(class, "px-")) {
        style.px = parseSpacing(class[3..]);
        return;
    }
    if (startsWith(class, "py-")) {
        style.py = parseSpacing(class[3..]);
        return;
    }

    // Background colors: bg-red-500, bg-slate-800, etc.
    if (startsWith(class, "bg-")) {
        style.bg = parseColor(class[3..]);
        return;
    }

    // Flex: flex-1, flex-2, etc.
    if (startsWith(class, "flex-")) {
        style.flex = parseInt(class[5..]);
        return;
    }

    // Rounded: rounded, rounded-lg, rounded-full
    if (eql(class, "rounded")) {
        style.rounded = .md;
        return;
    }
    if (eql(class, "rounded-lg")) {
        style.rounded = .lg;
        return;
    }

    // Unknown class - compile error!
    @compileError("Unknown Tailwind class: " ++ class);
}
```

## The Spacing Scale

Tailwind uses a consistent spacing scale:

```zig
fn parseSpacing(value: []const u8) i32 {
    // Tailwind scale: 1 = 4px, 2 = 8px, 4 = 16px, etc.
    const n = parseInt(value);
    return n * 4;
}

// So:
// gap-1  -> 4px
// gap-2  -> 8px
// gap-4  -> 16px
// p-6    -> 24px
```

This matches Tailwind CSS's 4px base unit.

## Color Parsing

Colors follow `{color}-{shade}` pattern:

```zig
fn parseColor(value: []const u8) ?Color {
    if (eql(value, "red-500")) return Color.red500;
    if (eql(value, "red-400")) return Color.red400;
    if (eql(value, "green-500")) return Color.green500;
    if (eql(value, "green-400")) return Color.green400;
    if (eql(value, "slate-800")) return Color.slate800;
    if (eql(value, "slate-900")) return Color.slate900;
    // ... more colors

    @compileError("Unknown color: " ++ value);
}
```

## Why Comptime?

All of this runs at **compile time**:

```zig
// At compile time, this:
const style = comptime tw("gap-4 p-6 bg-slate-800");

// Becomes this in the binary:
const style = Style{ .gap = 16, .p = 24, .bg = Color.slate800 };
```

Benefits:

1. **Zero runtime cost** - No string parsing when your app runs
2. **Compile-time errors** - Typo in class name? Won't compile
3. **Type safety** - Invalid values caught early

## Compile-Time Error Messages

If you typo a class:

```zig
jsx.col("gaap-4 p-6", &.{...})  // typo: "gaap" instead of "gap"
```

You get:
```
error: Unknown Tailwind class: gaap-4
```

At compile time. Not a runtime crash.

## Text Sizes

Text classes use a scale too:

```zig
if (eql(class, "text-sm")) {
    style.text_size = .sm;  // 14px
    return;
}
if (eql(class, "text-base")) {
    style.text_size = .base;  // 16px
    return;
}
if (eql(class, "text-xl")) {
    style.text_size = .xl;  // 20px
    return;
}
if (eql(class, "text-4xl")) {
    style.text_size = .x4l;  // 36px
    return;
}
```

## Adding New Classes

To add a new class, just add a pattern:

```zig
// Add support for "opacity-50", "opacity-75", etc.
if (startsWith(class, "opacity-")) {
    style.opacity = parseInt(class[8..]) / 100.0;
    return;
}
```

The pattern is simple:
1. Check prefix
2. Parse value
3. Set style field
4. Return

## Helper Functions

The parser uses a few helpers:

```zig
fn startsWith(str: []const u8, prefix: []const u8) bool {
    return str.len >= prefix.len and
           std.mem.eql(u8, str[0..prefix.len], prefix);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn parseInt(str: []const u8) i32 {
    return std.fmt.parseInt(i32, str, 10) catch 0;
}
```

## What's Next

We have nodes, builders, and styles. But how does a tree of nodes become pixels on screen? In Part 4, we'll build the renderer that walks the tree, calculates layout, and draws.
