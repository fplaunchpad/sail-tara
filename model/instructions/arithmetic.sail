/*!
@anchor section_arithmetic
=== Arithmetic

@anchor arithmetic
Results wrap at 16 bits, and nothing records a carry or an overflow.
 */

union clause instruction = ADD : (regidx, regidx, regidx)
mapping clause encdec = ADD(rd, rs1, rs2) <-> 0b01001 : opcode @ rd @ rs1 @ rs2 @ ignored(2)

/*!
@brief Add registers

Adds `rs1` and `rs2` into `rd`.

@param rd Destination register.
@param rs1 First source register.
@param rs2 Second source register.
@see ADDI, SUB
 */
function clause execute(ADD(rd, rs1, rs2)) = {
    X(rd) = X(rs1) + X(rs2)
}

union clause instruction = SUB : (regidx, regidx, regidx)
mapping clause encdec = SUB(rd, rs1, rs2) <-> 0b01010 : opcode @ rd @ rs1 @ rs2 @ ignored(2)

/*!
@brief Subtract registers

Subtracts `rs2` from `rs1` into `rd`.

@param rd Destination register.
@param rs1 First source register.
@param rs2 Second source register.
 */
function clause execute(SUB(rd, rs1, rs2)) = {
    X(rd) = X(rs1) - X(rs2)
}

union clause instruction = ADDI : (regidx, bits(8))
mapping clause encdec = ADDI(rd, imm) <-> 0b01011 : opcode @ rd @ imm

/*!
@brief Add immediate

Adds the immediate, sign-extended, to `rd`.

@param rd Destination register, read and written.
@param imm Signed immediate.
@note The signed immediate is added modulo 65536.
@see ADD, SUB
 */
function clause execute(ADDI(rd, imm)) = {
    X(rd) = X(rd) + signed(imm)
}

union clause instruction = MUL : (regidx, regidx, regidx)
mapping clause encdec = MUL(rd, rs1, rs2) <-> 0b01100 : opcode @ rd @ rs1 @ rs2 @ ignored(2)

/*!
@brief Multiply registers

Multiplies `rs1` by `rs2` into `rd`. It keeps the low 16 bits of the product, which are the same
for signed and unsigned operands.

@param rd Destination register.
@param rs1 First source register.
@param rs2 Second source register.
@note The low 16 product bits are identical for signed and unsigned multiplication.
 */
function clause execute(MUL(rd, rs1, rs2)) = {
    X(rd) = get_slice_int(16, unsigned(X(rs1)) * unsigned(X(rs2)), 0)
}
