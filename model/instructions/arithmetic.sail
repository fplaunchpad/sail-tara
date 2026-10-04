/*!
=== Arithmetic */
$anchor section_arithmetic

/*!
Results wrap at 16 bits, and nothing records a carry or an overflow. */
$anchor arithmetic

union clause instruction = ADD : (regidx, regidx, regidx)
function clause encode(ADD(rd, rs1, rs2)) = 0b01001 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01001 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(ADD(rd, rs1, rs2))
/*!
Adds `rs1` and `rs2` into `rd`. */
function clause execute(ADD(rd, rs1, rs2)) = {
    X(rd) = X(rs1) + X(rs2)
}

union clause instruction = SUB : (regidx, regidx, regidx)
function clause encode(SUB(rd, rs1, rs2)) = 0b01010 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01010 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(SUB(rd, rs1, rs2))
/*!
Subtracts `rs2` from `rs1` into `rd`. */
function clause execute(SUB(rd, rs1, rs2)) = {
    X(rd) = X(rs1) - X(rs2)
}

union clause instruction = ADDI : (regidx, bits(8))
function clause encode(ADDI(rd, imm)) = 0b01011 @ rd @ imm
function clause decode(0b01011 @ rd : regidx @ imm : bits(8)) = Some(ADDI(rd, imm))
/*!
Adds the immediate, sign-extended, to `rd`. */
function clause execute(ADDI(rd, imm)) = {
    X(rd) = X(rd) + signed(imm)
}

union clause instruction = MUL : (regidx, regidx, regidx)
function clause encode(MUL(rd, rs1, rs2)) = 0b01100 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01100 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(MUL(rd, rs1, rs2))
/*!
Multiplies `rs1` by `rs2` into `rd`. It keeps the low 16 bits of the product, which are the same
for signed and unsigned operands.
 */
function clause execute(MUL(rd, rs1, rs2)) = {
    X(rd) = get_slice_int(16, unsigned(X(rs1)) * unsigned(X(rs2)), 0)
}
