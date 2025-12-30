    .text
    .globl main
main:
    movl    $10, %eax       # eax = 10
    addl    $32, %eax       # eax = eax + 32 = 42
    ret                      # return eax as exit code
