/*!
=== Arithmetic */
$anchor section_arithmetic

/*!
Results wrap at 16 bits, and nothing records a carry or an overflow. */
$anchor arithmetic

union clause instruction = ADD : (regidx, regidx, regidx)
$[instruction_doc {
    title = "Add registers",
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
                title = "Wrap at 16 bits",
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
    notes = [],
    related = [ADDI, SUB],
}]
mapping clause encdec = ADD(rd, rs1, rs2) <-> 0b01001 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Adds `rs1` and `rs2` into `rd`. */
function clause execute(ADD(rd, rs1, rs2)) = {
    X(rd) = X(rs1) + X(rs2)
}

union clause instruction = SUB : (regidx, regidx, regidx)
$[instruction_doc {
    title = "Subtract registers",
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
                title = "Subtract past zero",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = rs1, value = "0b010" },
                        { name = rs2, value = "0b011" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0x0000" },
                        { "register" = GPR, index = 3, value = "0x0001" },
                    ],
                watch = [R1, R2, R3],
            },
        ],
    notes = [],
    related = [],
}]
mapping clause encdec = SUB(rd, rs1, rs2) <-> 0b01010 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Subtracts `rs2` from `rs1` into `rd`. */
function clause execute(SUB(rd, rs1, rs2)) = {
    X(rd) = X(rs1) - X(rs2)
}

union clause instruction = ADDI : (regidx, bits(8))
$[instruction_doc {
    title = "Add immediate",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = read_write,
                description = "Destination register",
            },
            { name = imm, interpretation = signed, access = value, description = Immediate },
        ],
    examples =
        [
            {
                title = "Add a negative immediate",
                operands = [{ name = rd, value = "0b011" }, { name = imm, value = "0xFF" }],
                before = [{ "register" = GPR, index = 3, value = "0x0000" }],
                watch = [R3],
            },
        ],
    notes = [{ category = architecture, text = "The signed immediate is added modulo 65536." }],
    related = [ADD, SUB],
}]
mapping clause encdec = ADDI(rd, imm) <-> 0b01011 : opcode @ rd @ imm
/*!
Adds the immediate, sign-extended, to `rd`. */
function clause execute(ADDI(rd, imm)) = {
    X(rd) = X(rd) + signed(imm)
}

union clause instruction = MUL : (regidx, regidx, regidx)
$[instruction_doc {
    title = "Multiply registers",
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
                title = "Keep the low half of the product",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = rs1, value = "0b010" },
                        { name = rs2, value = "0b011" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0x1234" },
                        { "register" = GPR, index = 3, value = "0x0010" },
                    ],
                watch = [R1, R2, R3],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    "The low 16 product bits are identical for signed and unsigned multiplication.",
            },
        ],
    related = [],
}]
mapping clause encdec = MUL(rd, rs1, rs2) <-> 0b01100 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Multiplies `rs1` by `rs2` into `rd`. It keeps the low 16 bits of the product, which are the same
for signed and unsigned operands.
 */
function clause execute(MUL(rd, rs1, rs2)) = {
    X(rd) = get_slice_int(16, unsigned(X(rs1)) * unsigned(X(rs2)), 0)
}
