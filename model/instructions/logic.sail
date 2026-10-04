/*!
=== Logic */
$anchor section_logic

/*!
The logic instructions are bitwise, on whole registers. */
$anchor logic

union clause instruction = AND : (regidx, regidx, regidx)
mapping clause encdec = AND(rd, rs1, rs2) <-> 0b01101 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Ands `rs1` and `rs2` into `rd`. */
function clause execute(AND(rd, rs1, rs2)) = {
    X(rd) = X(rs1) & X(rs2)
}

union clause instruction = OR : (regidx, regidx, regidx)
mapping clause encdec = OR(rd, rs1, rs2) <-> 0b01110 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Ors `rs1` and `rs2` into `rd`. */
function clause execute(OR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) | X(rs2)
}

union clause instruction = XOR : (regidx, regidx, regidx)
mapping clause encdec = XOR(rd, rs1, rs2) <-> 0b01111 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Exclusive-ors `rs1` and `rs2` into `rd`. */
function clause execute(XOR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) ^ X(rs2)
}

union clause instruction = NOT : (regidx, regidx)
mapping clause encdec = NOT(rd, rs) <-> 0b10000 : opcode @ rd @ rs @ ignored(5)
/*!
Complements `rs` into `rd`. */
function clause execute(NOT(rd, rs)) = {
    X(rd) = not_vec(X(rs))
}
