/*! Arithmetic wraps at 16 bits. There are no carry or overflow flags: the status flags of the RTL
are not modelled.
 */
$anchor arithmetic

union clause instruction = ADD : (regidx, regidx, regidx)
function clause encode(ADD(rd, rs1, rs2)) = 0b01001 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01001 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(ADD(rd, rs1, rs2))
/*! Adds `rs1` and `rs2` into `rd`, wrapping at 16 bits. */
function clause execute(ADD(rd, rs1, rs2)) = {
    X(rd) = X(rs1) + X(rs2)
}

union clause instruction = SUB : (regidx, regidx, regidx)
function clause encode(SUB(rd, rs1, rs2)) = 0b01010 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01010 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(SUB(rd, rs1, rs2))
/*! Subtracts `rs2` from `rs1` into `rd`, wrapping at 16 bits. */
function clause execute(SUB(rd, rs1, rs2)) = {
    X(rd) = X(rs1) - X(rs2)
}

union clause instruction = ADDI : (regidx, bits(8))
function clause encode(ADDI(rd, imm)) = 0b01011 @ rd @ imm
function clause decode(0b01011 @ rd : regidx @ imm : bits(8)) = Some(ADDI(rd, imm))
/*! Adds the immediate, sign-extended from 8 bits (-128 to 127), to `rd`, wrapping at 16 bits. */
function clause execute(ADDI(rd, imm)) = {
    X(rd) = X(rd) + signed(imm)
}

union clause instruction = MUL : (regidx, regidx, regidx)
function clause encode(MUL(rd, rs1, rs2)) = 0b01100 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01100 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(MUL(rd, rs1, rs2))
/*! Stores the low 16 bits of the product of `rs1` and `rs2` in `rd`. The low 16 bits are the same
whether the operands are read as signed or as unsigned.
 */
function clause execute(MUL(rd, rs1, rs2)) = {
    X(rd) = get_slice_int(16, unsigned(X(rs1)) * unsigned(X(rs2)), 0)
}
