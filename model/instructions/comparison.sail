/*!
@anchor section_comparison
=== Comparison

@anchor comparison
`SLT` is the only comparison, and it is signed. With no status flags, programs test its result
with `BZ` or `BN`.
 */

union clause instruction = SLT : (regidx, regidx, regidx)
mapping clause encdec = SLT(rd, rs1, rs2) <-> 0b10011 : opcode @ rd @ rs1 @ rs2 @ ignored(2)

/*!
@brief Set if less than

Sets `rd` to 1 if `rs1` is less than `rs2` as signed numbers, and to 0 otherwise.

@param rd Destination register.
@param rs1 First source register.
@param rs2 Second source register.
@usage Test the resulting zero or one with BZ or BN; comparison is signed.
 */
function clause execute(SLT(rd, rs1, rs2)) = {
    X(rd) = if signed(X(rs1)) < signed(X(rs2)) then { 0x0001 } else { 0x0000 }
}
