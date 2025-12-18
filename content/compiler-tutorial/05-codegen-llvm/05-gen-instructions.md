---
title: "5b.5: Generating Instructions"
weight: 5
---

# Lesson 5b.5: Generating Instructions

Convert AIR instructions to LLVM IR instructions.

---

## Goal

Generate LLVM IR for constants, arithmetic, and returns.

---

## Instruction Mapping

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    AIR TO LLVM INSTRUCTION MAPPING                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR Instruction        LLVM IR                                            │
│   ───────────────        ───────                                            │
│   const_i32(42)          Inline as literal: i32 42                          │
│   add_i32(%a, %b)        %result = add i32 %a, %b                           │
│   sub_i32(%a, %b)        %result = sub i32 %a, %b                           │
│   mul_i32(%a, %b)        %result = mul i32 %a, %b                           │
│   div_i32(%a, %b)        %result = sdiv i32 %a, %b                          │
│   neg_i32(%a)            %result = sub i32 0, %a                            │
│   ret(%val)              ret i32 %val                                       │
│   ret_void()             ret void                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Constants

LLVM constants are inlined, not separate instructions:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CONSTANT HANDLING                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR:                              LLVM IR:                                 │
│   ────                              ────────                                 │
│   %0 = const_i32(5)                 ; No separate instruction!              │
│   %1 = const_i32(3)                 ; Constants are inlined                 │
│   %2 = add_i32(%0, %1)              %2 = add i32 5, 3                       │
│                                                                              │
│   When generating, track which AIR values are constants                     │
│   and emit their literal values directly in operations.                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Value Tracking

We need to track what each AIR instruction produces:

```
struct ValueInfo:
    kind: enum { Constant, Instruction, Parameter }
    value: union {
        constant_value: i64,
        instruction_id: usize,
        param_index: usize,
    }

// Map AIR instruction index → how to reference it in LLVM
values: Map<usize, ValueInfo>
```

---

## Emitting Operands

```
function emitOperand(inst_ref, values) → string:
    info = values[inst_ref]

    switch info.kind:
        case Constant:
            return toString(info.constant_value)
        case Instruction:
            return "%" + toString(info.instruction_id)
        case Parameter:
            return "%p" + toString(info.param_index)
```

---

## Binary Operations

```
function generateBinaryOp(inst, op_name, values) → string:
    lhs = emitOperand(inst.lhs, values)
    rhs = emitOperand(inst.rhs, values)
    type_name = llvmType(inst.type)

    return "%" + inst.id + " = " + op_name + " " + type_name + " " + lhs + ", " + rhs
```

Example:
```
AIR:  %3 = add_i32(%1, %2)    where %1=5 (const), %2=param(0)
LLVM: %3 = add i32 5, %p0
```

---

## Negation

LLVM doesn't have a negate instruction. Use `sub 0, x`:

```
AIR:  %2 = neg_i32(%1)
LLVM: %2 = sub i32 0, %1
```

---

## Return Instructions

```
function generateReturn(inst, values) → string:
    if inst.type == Void:
        return "ret void"
    else:
        val = emitOperand(inst.value, values)
        return "ret " + llvmType(inst.type) + " " + val
```

---

## Complete Translation Example

```
AIR:
    function "calc":
        params: [I32, I32]
        return_type: I32
        body:
            %0 = param(0)           // a
            %1 = param(1)           // b
            %2 = const_i32(2)       // constant 2
            %3 = mul_i32(%1, %2)    // b * 2
            %4 = add_i32(%0, %3)    // a + (b * 2)
            %5 = ret(%4)

LLVM IR:
    define i32 @calc(i32 %p0, i32 %p1) {
    entry:
        %3 = mul i32 %p1, 2
        %4 = add i32 %p0, %3
        ret i32 %4
    }
```

Note: Constants are inlined, parameters become `%pN`.

---

## Instruction Generation Pseudocode

```
fn generateInstruction(self, inst: Instruction, values: *ValueMap) void:
    switch inst.tag:
        .const_i32, .const_i64 => {
            // Don't emit - constants are inlined
            values.put(inst.id, .{ .kind = .Constant, .value = inst.data });
        },

        .param => {
            values.put(inst.id, .{ .kind = .Parameter, .index = inst.data });
        },

        .add_i32 => {
            const lhs = self.emitOperand(inst.lhs, values);
            const rhs = self.emitOperand(inst.rhs, values);
            self.emit("%");
            self.emitInt(inst.id);
            self.emit(" = add i32 ");
            self.emit(lhs);
            self.emit(", ");
            self.emit(rhs);
            values.put(inst.id, .{ .kind = .Instruction, .id = inst.id });
        },

        .sub_i32 => {
            // Similar to add
        },

        .mul_i32 => {
            // Similar to add
        },

        .div_i32 => {
            // Use "sdiv" for signed division
        },

        .neg_i32 => {
            const operand = self.emitOperand(inst.operand, values);
            self.emit("%");
            self.emitInt(inst.id);
            self.emit(" = sub i32 0, ");
            self.emit(operand);
        },

        .ret => {
            const val = self.emitOperand(inst.operand, values);
            self.emit("ret i32 ");
            self.emit(val);
        },

        .ret_void => {
            self.emit("ret void");
        },
```

---

## Handling All Integer Sizes

```
function emitBinaryOp(inst, op, values) → string:
    lhs = emitOperand(inst.lhs, values)
    rhs = emitOperand(inst.rhs, values)

    type_str = switch inst.type:
        I8, U8   => "i8"
        I16, U16 => "i16"
        I32, U32 => "i32"
        I64, U64 => "i64"

    return "%" + inst.id + " = " + op + " " + type_str + " " + lhs + ", " + rhs
```

---

## Verify Your Understanding

### Question 1
Why don't we emit LLVM instructions for constants?

Answer: LLVM constants can be inlined directly in operations. `add i32 5, %x` is simpler than creating a named constant.

### Question 2
How do we implement negation in LLVM IR?

Answer: `sub i32 0, %x` - subtract the value from zero.

### Question 3
What's the difference between `sdiv` and `udiv`?

Answer: `sdiv` is signed division (respects sign bit), `udiv` is unsigned division (treats all bits as magnitude).

---

## What's Next

Let's learn how to build and run our generated LLVM IR.

Next: [Lesson 5b.6: Building and Running](../06-building-running/) →
