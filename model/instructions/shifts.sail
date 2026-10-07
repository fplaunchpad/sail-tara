/*!
@anchor section_shifts
=== Shifts

@anchor shifts
Both shifts are logical, and take their count from the low five bits of the immediate
(`shamt = imm8[4:0]`). The RTL does not say what a count of 16 or more does; the model shifts every
bit out, leaving zero.
 */
union clause instruction = SHL : (regidx, bits(8))
mapping clause encdec = SHL(rd, shamt) <-> 0b10001 : opcode @ rd @ shamt

/*!
@brief Logical shift left

Shifts `rd` left by `shamt[4:0]`, filling with zeros.

@param rd Destination register, read and written.
@param shamt Unsigned encoded shift count.
@note Only shamt[4:0] determines the shift count; the high three encoded bits do not affect
execution.
@assumption Counts 16 through 31 shift out every bit, leaving zero.
@see SHR
 */
function clause execute(SHL(rd, shamt)) = {
    X(rd) = sail_shiftleft(X(rd), unsigned(shamt[4 .. 0]))
}

union clause instruction = SHR : (regidx, bits(8))
mapping clause encdec = SHR(rd, shamt) <-> 0b10010 : opcode @ rd @ shamt

/*!
@brief Logical shift right

Shifts `rd` right by `shamt[4:0]`, filling with zeros.

@param rd Destination register, read and written.
@param shamt Unsigned encoded shift count.
@note Only shamt[4:0] determines the shift count; the high three encoded bits do not affect
execution.
@assumption Counts 16 through 31 shift out every bit, leaving zero.
@see SHL
 */
function clause execute(SHR(rd, shamt)) = {
    X(rd) = sail_shiftright(X(rd), unsigned(shamt[4 .. 0]))
}
