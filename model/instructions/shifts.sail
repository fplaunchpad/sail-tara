/*!
=== Shifts */
$anchor section_shifts

/*!
Both shifts are logical, and take their count from the low five bits of the immediate
(`shamt = imm8[4:0]`). The RTL does not say what a count of 16 or more does; the model shifts every
bit out, leaving zero.
 */
$anchor shifts

union clause instruction = SHL : (regidx, bits(8))
mapping clause encdec = SHL(rd, shamt) <-> 0b10001 : opcode @ rd @ shamt
/*!
Shifts `rd` left by `shamt[4:0]`, filling with zeros. */
function clause execute(SHL(rd, shamt)) = {
    X(rd) = sail_shiftleft(X(rd), unsigned(shamt[4 .. 0]))
}

union clause instruction = SHR : (regidx, bits(8))
mapping clause encdec = SHR(rd, shamt) <-> 0b10010 : opcode @ rd @ shamt
/*!
Shifts `rd` right by `shamt[4:0]`, filling with zeros. */
function clause execute(SHR(rd, shamt)) = {
    X(rd) = sail_shiftright(X(rd), unsigned(shamt[4 .. 0]))
}
