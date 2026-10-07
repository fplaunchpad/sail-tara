/*!
=== Comparison */
$anchor section_comparison

/*!
`SLT` is the only comparison, and it is signed. With no status flags, programs test its result
with `BZ` or `BN`.
 */
$anchor comparison

union clause instruction = SLT : (regidx, regidx, regidx)
$[instruction_doc {
    title = "Set if less than",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = write,
                description = "Destination register",
            },
            {
                name = rs1,
                interpretation = "register",
                access = read,
                description = "First source register",
            },
            {
                name = rs2,
                interpretation = "register",
                access = read,
                description = "Second source register",
            },
        ],
    examples =
        [
            {
                title = "Compare signed values",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = rs1, value = "0b010" },
                        { name = rs2, value = "0b011" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0xFFFF" },
                        { "register" = GPR, index = 3, value = "0x0001" },
                    ],
                watch = [R1, R2, R3],
            },
        ],
    notes =
        [
            {
                category = usage,
                text = "Test the resulting zero or one with BZ or BN; comparison is signed.",
            },
        ],
    related = [],
}]
mapping clause encdec = SLT(rd, rs1, rs2) <-> 0b10011 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Sets `rd` to 1 if `rs1` is less than `rs2` as signed numbers, and to 0 otherwise. */
function clause execute(SLT(rd, rs1, rs2)) = {
    X(rd) = if signed(X(rs1)) < signed(X(rs2)) then { 0x0001 } else { 0x0000 }
}
