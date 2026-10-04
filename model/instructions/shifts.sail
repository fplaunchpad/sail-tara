/*!
=== Shifts */
$anchor section_shifts

/*!
Both shifts are logical and take their count from the low five bits of the immediate ("shamt =
imm8[4:0]"); bits 7 to 5 of the field are ignored.
 */
$anchor shifts

union clause instruction = SHL : (regidx, bits(8))
function clause encode(SHL(rd, shamt)) = 0b10001 @ rd @ shamt
function clause decode(0b10001 @ rd : regidx @ shamt : bits(8)) = Some(SHL(rd, shamt))
/*!
Shifts `rd` left by `shamt[4:0]`; zeros enter at the right. The RTL does not say what a count of
16 or more does: the model shifts every bit out, giving zero.
 */
function clause execute(SHL(rd, shamt)) = {
    X(rd) = sail_shiftleft(X(rd), unsigned(shamt[4 .. 0]))
}

union clause instruction = SHR : (regidx, bits(8))
function clause encode(SHR(rd, shamt)) = 0b10010 @ rd @ shamt
function clause decode(0b10010 @ rd : regidx @ shamt : bits(8)) = Some(SHR(rd, shamt))
/*!
Shifts `rd` right by `shamt[4:0]`; zeros enter at the left. As for `SHL`, a count of 16 or more
gives zero.
 */
function clause execute(SHR(rd, shamt)) = {
    X(rd) = sail_shiftright(X(rd), unsigned(shamt[4 .. 0]))
}
