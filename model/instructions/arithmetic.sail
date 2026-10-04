/*!
=== Arithmetic */
$anchor section_arithmetic

/*!
Results wrap at 16 bits, and nothing records a carry or an overflow. */
$anchor arithmetic

union clause instruction = ADD : (regidx, regidx, regidx)
mapping clause encdec = ADD(rd, rs1, rs2) <-> 0b01001 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Adds `rs1` and `rs2` into `rd`. */
function clause execute(ADD(rd, rs1, rs2)) = {
    X(rd) = X(rs1) + X(rs2)
}

union clause instruction = SUB : (regidx, regidx, regidx)
mapping clause encdec = SUB(rd, rs1, rs2) <-> 0b01010 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Subtracts `rs2` from `rs1` into `rd`. */
function clause execute(SUB(rd, rs1, rs2)) = {
    X(rd) = X(rs1) - X(rs2)
}

union clause instruction = ADDI : (regidx, bits(8))
mapping clause encdec = ADDI(rd, imm) <-> 0b01011 : opcode @ rd @ imm
/*!
Adds the immediate, sign-extended, to `rd`. */
function clause execute(ADDI(rd, imm)) = {
    X(rd) = X(rd) + signed(imm)
}

union clause instruction = MUL : (regidx, regidx, regidx)
mapping clause encdec = MUL(rd, rs1, rs2) <-> 0b01100 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Multiplies `rs1` by `rs2` into `rd`. It keeps the low 16 bits of the product, which are the same
for signed and unsigned operands.
 */
function clause execute(MUL(rd, rs1, rs2)) = {
    X(rd) = get_slice_int(16, unsigned(X(rs1)) * unsigned(X(rs2)), 0)
}
