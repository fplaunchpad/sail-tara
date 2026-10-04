/*!
=== Control flow */
$anchor section_control_flow

/*!
A relative target is `PC + 2 + 2 * off`: the offset counts instructions from the next one. PC keeps
11 bits, so targets wrap around memory.
 */
$anchor control_flow

union clause instruction = BZ : (regidx, bits(8))
function clause encode(BZ(rs, off)) = 0b10100 @ rs @ off
function clause decode(0b10100 @ rs : regidx @ off : bits(8)) = Some(BZ(rs, off))
/*!
Branches if `rs` is zero, by -128 to 127 instructions. */
function clause execute(BZ(rs, off)) = {
    if X(rs) == 0x0000 then {
        nextPC = PC + 0x0002 + 2 * signed(off)
    }
}

union clause instruction = BN : (regidx, bits(8))
function clause encode(BN(rs, off)) = 0b10101 @ rs @ off
function clause decode(0b10101 @ rs : regidx @ off : bits(8)) = Some(BN(rs, off))
/*!
Branches if `rs` is negative, that is, if its bit 15 is set. */
function clause execute(BN(rs, off)) = {
    if X(rs)[15] == bitone then {
        nextPC = PC + 0x0002 + 2 * signed(off)
    }
}

union clause instruction = JMP : bits(11)
function clause encode(JMP(off)) = 0b10110 @ off
function clause decode(0b10110 @ off : bits(11)) = Some(JMP(off))
/*!
Jumps by -1024 to 1023 instructions, which reaches all of memory. */
function clause execute(JMP(off)) = {
    nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = CALL : bits(11)
function clause encode(CALL(off)) = 0b10111 @ off
function clause decode(0b10111 @ off : bits(11)) = Some(CALL(off))
/*!
Writes the return address, that of the next instruction, to R6 and jumps like `JMP`. It touches
neither R7 nor memory.
 */
function clause execute(CALL(off)) = {
    X(lr) = pc_mask(PC + 0x0002);
    nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = RET : unit
function clause encode(RET()) = 0b11000 @ 0b00000000000
function clause decode(0b11000 @ _ : bits(11)) = Some(RET())
/*!
Jumps to the address in R6. */
function clause execute(RET()) = {
    nextPC = X(lr)
}
