/*! `NOP` and `HLT` take no operands. `MOV` copies a register; `LIL` and `LIH` build a 16-bit
constant one byte at a time.
 */
$anchor data_movement

union clause instruction = NOP : unit
function clause encode(NOP()) = 0b00000 @ 0b00000000000
function clause decode(0b00000 @ _ : bits(11)) = Some(NOP())
/*! Does nothing. The instruction retires and PC moves to the next word. */
function clause execute(NOP()) = ()

union clause instruction = HLT : unit
function clause encode(HLT()) = 0b00001 @ 0b00000000000
function clause decode(0b00001 @ _ : bits(11)) = Some(HLT())
/*! Stops the CPU: sets the halt latch `HALTED`. `HLT` retires like any instruction, so PC advances
by 2. From then on `step` and `run_instruction` return `Stopped` until `reset` clears the latch.
 */
function clause execute(HLT()) = {
    HALTED = true
}

union clause instruction = MOV : (regidx, regidx)
function clause encode(MOV(rd, rs)) = 0b00010 @ rd @ rs @ 0b00000
function clause decode(0b00010 @ rd : regidx @ rs : regidx @ _ : bits(5)) = Some(MOV(rd, rs))
/*! Copies `rs` to `rd`. */
function clause execute(MOV(rd, rs)) = {
    X(rd) = X(rs)
}

union clause instruction = LIL : (regidx, bits(8))
function clause encode(LIL(rd, imm)) = 0b00011 @ rd @ imm
function clause decode(0b00011 @ rd : regidx @ imm : bits(8)) = Some(LIL(rd, imm))
/*! Loads the immediate into the low byte of `rd` and clears the upper byte. */
function clause execute(LIL(rd, imm)) = {
    X(rd) = 0x00 @ imm
}

union clause instruction = LIH : (regidx, bits(8))
function clause encode(LIH(rd, imm)) = 0b00100 @ rd @ imm
function clause decode(0b00100 @ rd : regidx @ imm : bits(8)) = Some(LIH(rd, imm))
/*! Loads the immediate into the upper byte of `rd` and leaves the low byte unchanged. `LIL`
followed by `LIH` builds any 16-bit constant.
 */
function clause execute(LIH(rd, imm)) = {
    X(rd) = imm @ X(rd)[7 .. 0]
}
