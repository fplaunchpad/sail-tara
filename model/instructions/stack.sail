/*!
=== Stack */
$anchor section_stack

/*!
The stack grows down from the address in R7, a word at a time, unchecked. Reset leaves R7 alone, so
a program sets it before its first `PUSH`. Each instruction takes its two steps in the order of the
ISA table, which shows when the register is R7 itself.
 */
$anchor stack

union clause instruction = PUSH : regidx
mapping clause encdec = PUSH(rs) <-> 0b11001 : opcode @ rs @ ignored(8)
/*!
Decrements R7 by 2, then stores `rs` at the address in R7, so `PUSH R7` stores the decremented
value.
 */
function clause execute(PUSH(rs)) = {
    X(sp) = X(sp) - 0x0002;
    write_word(X(sp), X(rs))
}

union clause instruction = POP : regidx
mapping clause encdec = POP(rd) <-> 0b11010 : opcode @ rd @ ignored(8)
/*!
Loads the word at the address in R7 into `rd`, then increments R7 by 2, so `POP R7` leaves the
loaded value plus 2.
 */
function clause execute(POP(rd)) = {
    X(rd) = read_word(X(sp));
    X(sp) = X(sp) + 0x0002
}
