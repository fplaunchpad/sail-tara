/*!
@anchor section_data_movement
=== Data movement

@anchor data_movement
`NOP` and `HLT` take no operands. `MOV` copies a register, and `LIL` and `LIH` load a 16-bit
constant a byte at a time.
 */

union clause instruction = NOP : unit
mapping clause encdec = NOP() <-> 0b00000 : opcode @ ignored(11)

/*!
@brief No operation

Does nothing. PC moves on to the next instruction.
 */
function clause execute(NOP()) = ()

union clause instruction = HLT : unit
mapping clause encdec = HLT() <-> 0b00001 : opcode @ ignored(11)

/*!
@brief Halt

Sets the halt latch. `HLT` retires, so PC moves past it; from then on `step` and `run_instruction`
return `Stopped` until `reset`.
@note HLT retires and advances PC before subsequent driver calls return Stopped.
 */
function clause execute(HLT()) = {
    HALTED = true
}

union clause instruction = MOV : (regidx, regidx)
mapping clause encdec = MOV(rd, rs) <-> 0b00010 : opcode @ rd @ rs @ ignored(5)

/*!
@brief Move register

Copies `rs` to `rd`.

@param rd Destination register.
@param rs Source register.
 */
function clause execute(MOV(rd, rs)) = {
    X(rd) = X(rs)
}

union clause instruction = LIL : (regidx, bits(8))
mapping clause encdec = LIL(rd, imm) <-> 0b00011 : opcode @ rd @ imm

/*!
@brief Load low immediate

Sets `rd` to the immediate, zero-extended.

@param rd Destination register.
@param imm Unsigned immediate value.
@note The high byte is cleared.
@see LIH
 */
function clause execute(LIL(rd, imm)) = {
    X(rd) = 0x00 @ imm
}

union clause instruction = LIH : (regidx, bits(8))
mapping clause encdec = LIH(rd, imm) <-> 0b00100 : opcode @ rd @ imm

/*!
@brief Load high immediate

Replaces the upper byte of `rd` with the immediate. After a `LIL`, it completes a 16-bit constant.

@param rd Destination register, read and written.
@param imm Unsigned immediate value.
@note The low byte of the destination is preserved.
@see LIL
 */
function clause execute(LIH(rd, imm)) = {
    X(rd) = imm @ X(rd)[7 .. 0]
}
