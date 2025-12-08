+++
title = "Building UIs in Zig: Part 0 - What We're Building"
date = 2024-12-08
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

## What We're Building

A complete UI framework with:

```
┌─────────────────────────────────────────────────────────────┐
│                     JSX Framework                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐       │
│  │   Builder   │   │   Tailwind  │   │   Events    │       │
│  │             │   │   Parser    │   │             │       │
│  │  jsx.col()  │   │             │   │ E.increment │       │
│  │  jsx.row()  │   │  "gap-4"    │   │ E.decrement │       │
│  │  jsx.text() │   │  "p-6"      │   │ handlers[]  │       │
│  │  jsx.btn()  │   │  "bg-red"   │   │             │       │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘       │
│         │                 │                 │               │
│         └────────┬────────┴────────┬────────┘               │
│                  │                 │                        │
│                  ▼                 ▼                        │
│         ┌─────────────┐   ┌─────────────┐                  │
│         │    Node     │   │   Renderer  │                  │
│         │    Tree     │──▶│             │                  │
│         │             │   │  • Layout   │                  │
│         │ kind: .col  │   │  • Draw     │                  │
│         │ style: {}   │   │  • Events   │                  │
│         │ children:[] │   │             │                  │
│         └─────────────┘   └─────────────┘                  │
│                                  │                          │
│                                  ▼                          │
│                          ┌─────────────┐                   │
│                          │   Raylib    │                   │
│                          │  (pixels)   │                   │
│                          └─────────────┘                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## The Key Ideas

### 1. Nodes as Data

UI elements are just structs:

```
┌──────────────────────────┐
│          Node            │
├──────────────────────────┤
│  kind: .col              │
│  style: { gap: 16 }      │
│  children: ─────────────────┐
│  props: { label: null }  │  │
└──────────────────────────┘  │
                              ▼
              ┌───────────────────────────┐
              │                           │
        ┌─────┴─────┐            ┌────────┴────────┐
        │   Node    │            │      Node       │
        │ kind:.text│            │  kind:.button   │
        │ "Counter" │            │  label: "+"     │
        └───────────┘            └─────────────────┘
```

### 2. Comptime Parsing

Tailwind classes are parsed at compile time:

```
Compile Time                              Binary
─────────────                             ──────
"gap-4 p-6 bg-slate-800"     ──▶     Style {
                                        .gap = 16,
                                        .p = 24,
                                        .bg = slate800
                                     }
```

Zero runtime cost. Typos caught at compile time.

### 3. Index-Based Events

No closures. No allocations. Just array indices:

```
┌─────────────────────────────────────────────┐
│                                             │
│  E = enum { increment, decrement, reset }   │
│              0          1          2        │
│                                             │
│  handlers = [ onIncr,  onDecr,   onReset ]  │
│               [0]       [1]       [2]       │
│                                             │
│  button.onPress(E.increment)                │
│         └─────▶ stores 0                    │
│                                             │
│  on click: handlers[0]() ──▶ onIncr()       │
│                                             │
└─────────────────────────────────────────────┘
```

### 4. Immediate Mode

Every frame:

```
┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
│ State  │───▶│ Build  │───▶│ Render │───▶│ Events │──┐
│count=5 │    │  Tree  │    │ Pixels │    │ Queue  │  │
└────────┘    └────────┘    └────────┘    └────────┘  │
     ▲                                                 │
     └─────────────────────────────────────────────────┘
                         next frame
```

No virtual DOM. No diffing. Just rebuild.

## The Series

1. **Part 1: Imperative vs Declarative** - Why we're doing this
2. **Part 2: Your First Counter App** - Using the framework
3. **Part 3: How the Renderer Works** - Tree walking and layout
4. **Part 4: Comptime Tailwind Parser** - Zero-cost styling
5. **Part 5: Complete Architecture** - Putting it together
6. **Part 6: Behind the Scenes** - Deep dive with real code

## Prerequisites

- Basic Zig knowledge (structs, slices, comptime)
- Curiosity about UI frameworks
- That's it!

## Let's Go

Ready? In Part 1, we'll understand why declarative beats imperative.
