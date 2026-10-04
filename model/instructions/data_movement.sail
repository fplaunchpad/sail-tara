/*!
=== Data movement */
$anchor section_data_movement

/*!
`NOP` and `HLT` take no operands. `MOV` copies a register, and `LIL` and `LIH` load a 16-bit
constant a byte at a time.
 */
$anchor data_movement

union clause instruction = NOP : unit
function clause encode(NOP()) = 0b00000 @ 0b00000000000
function clause decode(0b00000 @ _ : bits(11)) = Some(NOP())
/*!
Does nothing. PC moves on to the next instruction. */
function clause execute(NOP()) = ()

union clause instruction = HLT : unit
function clause encode(HLT()) = 0b00001 @ 0b00000000000
function clause decode(0b00001 @ _ : bits(11)) = Some(HLT())
/*!
Sets the halt latch. `HLT` retires, so PC moves past it; from then on `step` and `run_instruction`
return `Stopped` until `reset`.
 */
function clause execute(HLT()) = {
    HALTED = true
}

union clause instruction = MOV : (regidx, regidx)
function clause encode(MOV(rd, rs)) = 0b00010 @ rd @ rs @ 0b00000
function clause decode(0b00010 @ rd : regidx @ rs : regidx @ _ : bits(5)) = Some(MOV(rd, rs))
/*!
Copies `rs` to `rd`. */
function clause execute(MOV(rd, rs)) = {
    X(rd) = X(rs)
}

union clause instruction = LIL : (regidx, bits(8))
function clause encode(LIL(rd, imm)) = 0b00011 @ rd @ imm
function clause decode(0b00011 @ rd : regidx @ imm : bits(8)) = Some(LIL(rd, imm))
/*!
Sets `rd` to the immediate, zero-extended. */
function clause execute(LIL(rd, imm)) = {
    X(rd) = 0x00 @ imm
}

union clause instruction = LIH : (regidx, bits(8))
function clause encode(LIH(rd, imm)) = 0b00100 @ rd @ imm
function clause decode(0b00100 @ rd : regidx @ imm : bits(8)) = Some(LIH(rd, imm))
/*!
Replaces the upper byte of `rd` with the immediate. After a `LIL`, it completes a 16-bit constant.
 */
function clause execute(LIH(rd, imm)) = {
    X(rd) = imm @ X(rd)[7 .. 0]
}
