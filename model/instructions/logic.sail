/*!
@anchor section_logic
=== Logic

@anchor logic
The logic instructions are bitwise, on whole registers.
 */
union clause instruction = AND : (regidx, regidx, regidx)
mapping clause encdec = AND(rd, rs1, rs2) <-> 0b01101 : opcode @ rd @ rs1 @ rs2 @ ignored(2)

/*!
@brief Bitwise AND

Ands `rs1` and `rs2` into `rd`.

@param rd Destination register.
@param rs1 First source register.
@param rs2 Second source register.
 */
function clause execute(AND(rd, rs1, rs2)) = {
    X(rd) = X(rs1) & X(rs2)
}

union clause instruction = OR : (regidx, regidx, regidx)
mapping clause encdec = OR(rd, rs1, rs2) <-> 0b01110 : opcode @ rd @ rs1 @ rs2 @ ignored(2)

/*!
@brief Bitwise OR

Ors `rs1` and `rs2` into `rd`.

@param rd Destination register.
@param rs1 First source register.
@param rs2 Second source register.
 */
function clause execute(OR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) | X(rs2)
}

union clause instruction = XOR : (regidx, regidx, regidx)
mapping clause encdec = XOR(rd, rs1, rs2) <-> 0b01111 : opcode @ rd @ rs1 @ rs2 @ ignored(2)

/*!
@brief Bitwise exclusive OR

Exclusive-ors `rs1` and `rs2` into `rd`.

@param rd Destination register.
@param rs1 First source register.
@param rs2 Second source register.
 */
function clause execute(XOR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) ^ X(rs2)
}

union clause instruction = NOT : (regidx, regidx)
mapping clause encdec = NOT(rd, rs) <-> 0b10000 : opcode @ rd @ rs @ ignored(5)

/*!
@brief Bitwise complement

Complements `rs` into `rd`.

@param rd Destination register.
@param rs Source register.
 */
function clause execute(NOT(rd, rs)) = {
    X(rd) = not_vec(X(rs))
}
