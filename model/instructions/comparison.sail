/*!
=== Comparison */
$anchor section_comparison

/*! `SLT` is the only comparison, and it compares signed numbers. There is no unsigned comparison
and no status flag to test: a program tests the result register with `BZ` or `BN`.
 */
$anchor comparison

union clause instruction = SLT : (regidx, regidx, regidx)
function clause encode(SLT(rd, rs1, rs2)) = 0b10011 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b10011 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(SLT(rd, rs1, rs2))
/*! Sets `rd` to 1 if `rs1` is less than `rs2`, both read as signed 16-bit numbers, and to 0
otherwise.
 */
function clause execute(SLT(rd, rs1, rs2)) = {
    X(rd) = if signed(X(rs1)) < signed(X(rs2)) then { 0x0001 } else { 0x0000 }
}
