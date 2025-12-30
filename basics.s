    .text
    .globl _main
_main:
    // Save frame pointer and link register
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Simple arithmetic: (10 + 5) * 2 = 30
    mov     w0, #10         // w0 = 10
    mov     w1, #5          // w1 = 5
    add     w2, w0, w1      // w2 = 15
    mov     w3, #2          // w3 = 2
    mul     w0, w2, w3      // w0 = 30 (result for return)

    // Restore and return
    ldp     x29, x30, [sp], #16
    ret
