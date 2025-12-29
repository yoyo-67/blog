define i32 @main() {
entry:
    %2 = call i32 @math_add(i32 10, i32 5)
    %6 = call i32 @math_multiply(i32 3, i32 4)
    %9 = call i32 @math_square(i32 %2)
    %12 = call i32 @str_double(i32 %6)
    %16 = add i32 %9, %12
    ret i32 %16
}


define i32 @add(i32 %p0, i32 %p1) {
entry:
    %2 = add i32 %p0, %p1
    ret i32 %2
}

define i32 @multiply(i32 %p0, i32 %p1) {
entry:
    %2 = mul i32 %p0, %p1
    %4 = add i32 %2, 0
    ret i32 %4
}

define i32 @square(i32 %p0) {
entry:
    %2 = mul i32 %p0, %p0
    ret i32 %2
}


define i32 @length(i32 %p0) {
entry:
    %2 = add i32 %p0, 1
    ret i32 %2
}

define i32 @double(i32 %p0) {
entry:
    %2 = mul i32 %p0, 2
    ret i32 %2
}


