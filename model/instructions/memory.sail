/*!
=== Memory */
$anchor section_memory

/*!
A load or store addresses `base + off`, where `off` counts bytes, -16 to 15, and the sum wraps at
16 bits. Memory uses only the low 11 address bits; a word access ignores bit 0. The byte at
`0x5FF` reads as the input port.
 */
$anchor memory

union clause instruction = LDW : (regidx, regidx, bits(5))
$[instruction_doc {
    title = "Load word",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = write,
                description = "Destination register",
            },
            {
                name = base,
                interpretation = "register",
                access = read,
                description = "Base address register",
            },
            {
                name = off,
                interpretation = signed,
                access = value,
                description = "Address displacement",
                unit = bytes,
            },
        ],
    examples =
        [
            {
                title = "An odd effective address",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = base, value = "0b010" },
                        { name = off, value = "0b11111" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0x0402" },
                        { "register" = MEM, index = 1024, value = "0x12" },
                        { "register" = MEM, index = 1025, value = "0x34" },
                    ],
                watch = [R1, R2],
            },
            {
                title = "Read across the input port",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = base, value = "0b010" },
                        { name = off, value = "0b00000" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0x05FE" },
                        { "register" = MEM, index = 1534, value = "0xAA" },
                    ],
                watch = [R1, R2],
                arguments = ["0b10101"],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    """
                    The effective address wraps to 16 bits. Memory keeps its low 11 bits and
                                        ignores bit 0 for word access.
                    """,
            },
            {
                category = assumption,
                text = "A word covering the input port reads the input lines as its low byte.",
            },
        ],
    related = [LDB, STW],
}]
mapping clause encdec = LDW(rd, base, off) <-> 0b00101 : opcode @ rd @ base @ off
/*!
Loads the word at `base + off` into `rd`. */
function clause execute(LDW(rd, base, off)) = {
    X(rd) = read_word(X(base) + signed(off))
}

union clause instruction = STW : (regidx, regidx, bits(5))
$[instruction_doc {
    title = "Store word",
    operands =
        [
            {
                name = rs,
                interpretation = "register",
                access = read,
                description = "Source register",
            },
            {
                name = base,
                interpretation = "register",
                access = read,
                description = "Base address register",
            },
            {
                name = off,
                interpretation = signed,
                access = value,
                description = "Address displacement",
                unit = bytes,
            },
        ],
    examples =
        [
            {
                title = "Store high byte first",
                operands =
                    [
                        { name = rs, value = "0b001" },
                        { name = base, value = "0b010" },
                        { name = off, value = "0b11111" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 1, value = "0xABCD" },
                        { "register" = GPR, index = 2, value = "0x0402" },
                    ],
                watch = [R1, R2],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    """
                    The effective address wraps to 16 bits. Word stores ignore address bit 0 and
                                        write the high byte first.
                    """,
            },
        ],
    related = [STB, LDW],
}]
mapping clause encdec = STW(rs, base, off) <-> 0b00110 : opcode @ rs @ base @ off
/*!
Stores `rs` as the word at `base + off`. */
function clause execute(STW(rs, base, off)) = {
    write_word(X(base) + signed(off), X(rs))
}

union clause instruction = LDB : (regidx, regidx, bits(5))
$[instruction_doc {
    title = "Load byte",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = write,
                description = "Destination register",
            },
            {
                name = base,
                interpretation = "register",
                access = read,
                description = "Base address register",
            },
            {
                name = off,
                interpretation = signed,
                access = value,
                description = "Address displacement",
                unit = bytes,
            },
        ],
    examples =
        [
            {
                title = "Zero-extend a byte",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = base, value = "0b010" },
                        { name = off, value = "0b00000" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0x0401" },
                        { "register" = MEM, index = 1025, value = "0xAB" },
                    ],
                watch = [R1, R2],
            },
            {
                title = "Read the live input lines",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = base, value = "0b010" },
                        { name = off, value = "0b00000" },
                    ],
                before = [{ "register" = GPR, index = 2, value = "0x05FF" }],
                watch = [R1, R2],
                arguments = ["0b10101"],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    """
                    The byte is zero-extended to 16 bits. Only the low 11 address bits select
                                        memory.
                    """,
            },
        ],
    related = [LDW, STB],
}]
mapping clause encdec = LDB(rd, base, off) <-> 0b00111 : opcode @ rd @ base @ off
/*!
Loads the byte at `base + off` into `rd`, zero-extended. */
function clause execute(LDB(rd, base, off)) = {
    X(rd) = 0x00 @ read_byte(X(base) + signed(off))
}

union clause instruction = STB : (regidx, regidx, bits(5))
$[instruction_doc {
    title = "Store byte",
    operands =
        [
            {
                name = rs,
                interpretation = "register",
                access = read,
                description = "Source register",
            },
            {
                name = base,
                interpretation = "register",
                access = read,
                description = "Base address register",
            },
            {
                name = off,
                interpretation = signed,
                access = value,
                description = "Address displacement",
                unit = bytes,
            },
        ],
    examples =
        [
            {
                title = "Store only the low byte",
                operands =
                    [
                        { name = rs, value = "0b001" },
                        { name = base, value = "0b010" },
                        { name = off, value = "0b11111" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 1, value = "0xABCD" },
                        { "register" = GPR, index = 2, value = "0x0402" },
                    ],
                watch = [R1, R2],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text = "Only the low byte of the source register is stored.",
            },
            {
                category = assumption,
                text =
                    """
                    A store to the input port writes the RAM byte behind it; reads return the
                                        input lines.
                    """,
            },
        ],
    related = [STW, LDB],
}]
mapping clause encdec = STB(rs, base, off) <-> 0b01000 : opcode @ rs @ base @ off
/*!
Stores the low byte of `rs` at `base + off`. */
function clause execute(STB(rs, base, off)) = {
    write_byte(X(base) + signed(off), X(rs)[7 .. 0])
}
