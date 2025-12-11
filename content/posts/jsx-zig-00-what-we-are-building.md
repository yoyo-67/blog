+++
title = "Building UIs in Zig: Part 0 - What We're Building"
date = 2025-12-11
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial", "introduction"]
+++

Welcome to the "Building UIs in Zig" series. We're going to build a declarative UI framework from scratch - no dependencies except Raylib for rendering.

## The End Result

By the end of this series, you'll have a framework that lets you write UI like this:

```zig
const view = jsx.col("gap-4 p-6 bg-slate-900", &.{
    jsx.h1("Counter"),
    jsx.text(count_str, "text-4xl font-bold")
        .fg(if (count >= 0) .green400 else .red400),
    jsx.row("gap-4", &.{
        jsx.button("-", "bg-red-500 rounded").onPress(E.decrement),
        jsx.button("+", "bg-green-500 rounded").onPress(E.increment),
    }),
});
```

And it becomes this:

```
┌────────────────────────────────────────┐
│                                        │
│            Counter                     │
│                                        │
│              42                        │
│                                        │
│       ┌─────┐        ┌─────┐          │
│       │  -  │        │  +  │          │
│       └─────┘        └─────┘          │
│                                        │
└────────────────────────────────────────┘
```

No manual coordinates. No pixel pushing. Just describe the structure.

By the end of this series, you'll understand every line of that code and how it all works under the hood.

## The Series

We'll build this framework step by step, from the ground up:

1. **Part 1: The Building Block - Nodes** - UI elements as data structures
2. **Part 2: Building Nodes** - How jsx.col(), jsx.text(), jsx.button() work
3. **Part 3: Styling** - Comptime Tailwind parser for zero-cost styling
4. **Part 4: Rendering** - From node tree to pixels on screen
5. **Part 5: Events** - Connecting buttons to actions
6. **Part 6: Imperative vs Declarative** - Why this approach wins
7. **Part 7: Your First Counter App** - Putting it all together
8. **Part 8: The Complete Architecture** - The big picture

## Prerequisites

- Basic Zig knowledge (structs, slices, comptime)
- Curiosity about UI frameworks
- That's it!

## Let's Go

Ready? In Part 1, we'll start with the fundamental building block: the Node.
