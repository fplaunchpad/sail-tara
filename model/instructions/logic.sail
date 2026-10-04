/*!
=== Logic */
$anchor section_logic

/*! The logic instructions work on all 16 bits at once. */
$anchor logic

union clause instruction = AND : (regidx, regidx, regidx)
function clause encode(AND(rd, rs1, rs2)) = 0b01101 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01101 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(AND(rd, rs1, rs2))
/*! Bitwise and of `rs1` and `rs2` into `rd`. */
function clause execute(AND(rd, rs1, rs2)) = {
    X(rd) = X(rs1) & X(rs2)
}

union clause instruction = OR : (regidx, regidx, regidx)
function clause encode(OR(rd, rs1, rs2)) = 0b01110 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01110 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(OR(rd, rs1, rs2))
/*! Bitwise or of `rs1` and `rs2` into `rd`. */
function clause execute(OR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) | X(rs2)
}

union clause instruction = XOR : (regidx, regidx, regidx)
function clause encode(XOR(rd, rs1, rs2)) = 0b01111 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01111 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(XOR(rd, rs1, rs2))
/*! Bitwise exclusive or of `rs1` and `rs2` into `rd`. */
function clause execute(XOR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) ^ X(rs2)
}

union clause instruction = NOT : (regidx, regidx)
function clause encode(NOT(rd, rs)) = 0b10000 @ rd @ rs @ 0b00000
function clause decode(0b10000 @ rd : regidx @ rs : regidx @ _ : bits(5)) = Some(NOT(rd, rs))
/*! Bitwise complement of `rs` into `rd`. */
function clause execute(NOT(rd, rs)) = {
    X(rd) = not_vec(X(rs))
}
