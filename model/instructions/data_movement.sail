/*!
=== Data movement */
$anchor section_data_movement

/*!
`NOP` and `HLT` take no operands. `MOV` copies a register, and `LIL` and `LIH` load a 16-bit
constant a byte at a time.
 */
$anchor data_movement

union clause instruction = NOP : unit
mapping clause encdec = NOP() <-> 0b00000 : opcode @ ignored(11)
/*!
Does nothing. PC moves on to the next instruction. */
function clause execute(NOP()) = ()

union clause instruction = HLT : unit
mapping clause encdec = HLT() <-> 0b00001 : opcode @ ignored(11)
/*!
Sets the halt latch. `HLT` retires, so PC moves past it; from then on `step` and `run_instruction`
return `Stopped` until `reset`.
 */
function clause execute(HLT()) = {
    HALTED = true
}

union clause instruction = MOV : (regidx, regidx)
mapping clause encdec = MOV(rd, rs) <-> 0b00010 : opcode @ rd @ rs @ ignored(5)
/*!
Copies `rs` to `rd`. */
function clause execute(MOV(rd, rs)) = {
    X(rd) = X(rs)
}

union clause instruction = LIL : (regidx, bits(8))
mapping clause encdec = LIL(rd, imm) <-> 0b00011 : opcode @ rd @ imm
/*!
Sets `rd` to the immediate, zero-extended. */
function clause execute(LIL(rd, imm)) = {
    X(rd) = 0x00 @ imm
}

union clause instruction = LIH : (regidx, bits(8))
mapping clause encdec = LIH(rd, imm) <-> 0b00100 : opcode @ rd @ imm
/*!
Replaces the upper byte of `rd` with the immediate. After a `LIL`, it completes a 16-bit constant.
 */
function clause execute(LIH(rd, imm)) = {
    X(rd) = imm @ X(rd)[7 .. 0]
}
