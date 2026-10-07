/*!
=== Shifts */
$anchor section_shifts

/*!
Both shifts are logical, and take their count from the low five bits of the immediate
(`shamt = imm8[4:0]`). The RTL does not say what a count of 16 or more does; the model shifts every
bit out, leaving zero.
 */
$anchor shifts

union clause instruction = SHL : (regidx, bits(8))
$[instruction_doc {
    title = "Logical shift left",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = read_write,
                description = "Destination register",
            },
            {
                name = shamt,
                interpretation = unsigned,
                access = value,
                description = "Encoded shift count",
            },
        ],
    examples =
        [
            {
                title = "Shift by one",
                operands = [{ name = rd, value = "0b001" }, { name = shamt, value = "0x01" }],
                before = [{ "register" = GPR, index = 1, value = "0x8001" }],
                watch = [R1],
            },
            {
                title = "Shift every bit out",
                operands = [{ name = rd, value = "0b001" }, { name = shamt, value = "0x10" }],
                before = [{ "register" = GPR, index = 1, value = "0x8001" }],
                watch = [R1],
            },
            {
                title = "The count wraps to zero",
                operands = [{ name = rd, value = "0b001" }, { name = shamt, value = "0x20" }],
                before = [{ "register" = GPR, index = 1, value = "0x8001" }],
                watch = [R1],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    """
                    Only shamt[4:0] determines the shift count; the high three encoded bits do not
                                        affect execution.
                    """,
            },
            {
                category = assumption,
                text = "Counts 16 through 31 shift out every bit, leaving zero.",
            },
        ],
    related = [SHR],
}]
mapping clause encdec = SHL(rd, shamt) <-> 0b10001 : opcode @ rd @ shamt
/*!
Shifts `rd` left by `shamt[4:0]`, filling with zeros. */
function clause execute(SHL(rd, shamt)) = {
    X(rd) = sail_shiftleft(X(rd), unsigned(shamt[4 .. 0]))
}

union clause instruction = SHR : (regidx, bits(8))
$[instruction_doc {
    title = "Logical shift right",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = read_write,
                description = "Destination register",
            },
            {
                name = shamt,
                interpretation = unsigned,
                access = value,
                description = "Encoded shift count",
            },
        ],
    examples =
        [
            {
                title = "Shift by one",
                operands = [{ name = rd, value = "0b001" }, { name = shamt, value = "0x01" }],
                before = [{ "register" = GPR, index = 1, value = "0x8001" }],
                watch = [R1],
            },
            {
                title = "Shift every bit out",
                operands = [{ name = rd, value = "0b001" }, { name = shamt, value = "0x10" }],
                before = [{ "register" = GPR, index = 1, value = "0x8001" }],
                watch = [R1],
            },
            {
                title = "The count wraps to zero",
                operands = [{ name = rd, value = "0b001" }, { name = shamt, value = "0x20" }],
                before = [{ "register" = GPR, index = 1, value = "0x8001" }],
                watch = [R1],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    """
                    Only shamt[4:0] determines the shift count; the high three encoded bits do not
                                        affect execution.
                    """,
            },
            {
                category = assumption,
                text = "Counts 16 through 31 shift out every bit, leaving zero.",
            },
        ],
    related = [SHL],
}]
mapping clause encdec = SHR(rd, shamt) <-> 0b10010 : opcode @ rd @ shamt
/*!
Shifts `rd` right by `shamt[4:0]`, filling with zeros. */
function clause execute(SHR(rd, shamt)) = {
    X(rd) = sail_shiftright(X(rd), unsigned(shamt[4 .. 0]))
}
