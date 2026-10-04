/*!
=== Control flow */
$anchor section_control_flow

/*!
A relative target is `PC + 2 + 2 * off`: the offset counts instructions from the next one. PC keeps
11 bits, so targets wrap around memory.
 */
$anchor control_flow

union clause instruction = BZ : (regidx, bits(8))
mapping clause encdec = BZ(rs, off) <-> 0b10100 : opcode @ rs @ off
/*!
Branches if `rs` is zero, by -128 to 127 instructions. */
function clause execute(BZ(rs, off)) = {
    if X(rs) == 0x0000 then {
        nextPC = PC + 0x0002 + 2 * signed(off)
    }
}

union clause instruction = BN : (regidx, bits(8))
mapping clause encdec = BN(rs, off) <-> 0b10101 : opcode @ rs @ off
/*!
Branches if `rs` is negative, that is, if its bit 15 is set. */
function clause execute(BN(rs, off)) = {
    if X(rs)[15] == bitone then {
        nextPC = PC + 0x0002 + 2 * signed(off)
    }
}

union clause instruction = JMP : bits(11)
mapping clause encdec = JMP(off) <-> 0b10110 : opcode @ off
/*!
Jumps by -1024 to 1023 instructions, which reaches all of memory. */
function clause execute(JMP(off)) = {
    nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = CALL : bits(11)
mapping clause encdec = CALL(off) <-> 0b10111 : opcode @ off
/*!
Writes the return address, that of the next instruction, to R6 and jumps like `JMP`. It touches
neither R7 nor memory.
 */
function clause execute(CALL(off)) = {
    X(lr) = pc_mask(PC + 0x0002);
    nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = RET : unit
mapping clause encdec = RET() <-> 0b11000 : opcode @ ignored(11)
/*!
Jumps to the address in R6. */
function clause execute(RET()) = {
    nextPC = X(lr)
}
