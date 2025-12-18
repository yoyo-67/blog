---
title: "5b.3: Type Mapping"
weight: 3
---

# Lesson 5b.3: Type Mapping

Map our compiler's types to LLVM IR types.

---

## Goal

Convert AIR types to their LLVM IR equivalents.

---

## Type Mapping Table

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         TYPE MAPPING                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Our Type     LLVM Type     Notes                                          │
│   ────────     ─────────     ─────                                          │
│   i8           i8            8-bit signed integer                           │
│   i16          i16           16-bit signed integer                          │
│   i32          i32           32-bit signed integer                          │
│   i64          i64           64-bit signed integer                          │
│   u8           i8            LLVM integers are signless*                    │
│   u16          i16           Sign matters in operations, not types          │
│   u32          i32                                                          │
│   u64          i64                                                          │
│   bool         i1            1-bit integer                                  │
│   void         void          No value                                       │
│                                                                              │
│   * LLVM uses signed/unsigned operations, not types                         │
│     sdiv = signed division, udiv = unsigned division                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Type Conversion Function

```
function llvmType(airType) → string:
    switch airType:
        case I8, U8:   return "i8"
        case I16, U16: return "i16"
        case I32, U32: return "i32"
        case I64, U64: return "i64"
        case Bool:     return "i1"
        case Void:     return "void"
```

---

## Signedness in LLVM

LLVM types don't carry signedness. Instead, operations do:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    SIGNED vs UNSIGNED OPERATIONS                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Operation          Signed         Unsigned                                 │
│   ─────────          ──────         ────────                                 │
│   Division           sdiv           udiv                                     │
│   Remainder          srem           urem                                     │
│   Right shift        ashr           lshr                                     │
│   Comparison <       icmp slt       icmp ult                                │
│   Comparison >       icmp sgt       icmp ugt                                │
│   Extend             sext           zext                                     │
│                                                                              │
│   Addition and multiplication are the same for signed/unsigned!             │
│   (Two's complement makes them equivalent)                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Example: Type Mapping in Action

```
AIR:
    function "calculate":
        params: [(a, I32), (b, I32)]
        return_type: I32
        body:
            %0 = param(0)          // type: I32
            %1 = param(1)          // type: I32
            %2 = add_i32(%0, %1)   // type: I32
            %3 = ret(%2)

LLVM IR:
    define i32 @calculate(i32 %a, i32 %b) {
    entry:
        %0 = add i32 %a, %b
        ret i32 %0
    }
```

---

## Handling Booleans

Our `bool` maps to LLVM's `i1`:

```
Our Code:
    const flag: bool = true;

LLVM IR:
    %flag = add i1 0, 1    ; true = 1
    ; or simply use the constant:
    %flag = i1 1
```

For conditionals:
```llvm
; i1 is used directly in branches
%cond = icmp eq i32 %a, %b    ; Returns i1
br i1 %cond, label %then, label %else
```

---

## Type Conversion Pseudocode

```
struct LLVMCodegen:
    fn emitType(self, air_type: Type) void:
        const llvm_type = switch air_type:
            .i8, .u8 => "i8",
            .i16, .u16 => "i16",
            .i32, .u32 => "i32",
            .i64, .u64 => "i64",
            .bool => "i1",
            .void => "void",

        self.emit(llvm_type)
```

---

## Comparison with C Backend

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    C vs LLVM TYPE MAPPING                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Our Type     C Type          LLVM Type                                    │
│   ────────     ──────          ─────────                                    │
│   i32          int32_t         i32                                          │
│   u32          uint32_t        i32                                          │
│   bool         bool            i1                                           │
│   void         void            void                                         │
│                                                                              │
│   C distinguishes signed/unsigned in types                                   │
│   LLVM distinguishes signed/unsigned in operations                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Understanding

### Question 1
How does LLVM represent our `u32` type?

Answer: As `i32`. LLVM integers don't carry signedness - we use unsigned operations (udiv, urem) when needed.

### Question 2
What LLVM type represents a boolean?

Answer: `i1` (1-bit integer). 0 = false, 1 = true.

---

## What's Next

Let's generate LLVM function definitions.

Next: [Lesson 5b.4: Generating Functions](../04-gen-functions/) →
