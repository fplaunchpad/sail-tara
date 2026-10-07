/*!
=== Logic */
$anchor section_logic

/*!
The logic instructions are bitwise, on whole registers. */
$anchor logic

union clause instruction = AND : (regidx, regidx, regidx)
$[instruction_doc {
    title = "Bitwise AND",
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
                title = "Combine two bit patterns",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = rs1, value = "0b010" },
                        { name = rs2, value = "0b011" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0xF0F0" },
                        { "register" = GPR, index = 3, value = "0x0FF0" },
                    ],
                watch = [R1, R2, R3],
            },
        ],
    notes = [],
    related = [],
}]
mapping clause encdec = AND(rd, rs1, rs2) <-> 0b01101 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Ands `rs1` and `rs2` into `rd`. */
function clause execute(AND(rd, rs1, rs2)) = {
    X(rd) = X(rs1) & X(rs2)
}

union clause instruction = OR : (regidx, regidx, regidx)
$[instruction_doc {
    title = "Bitwise OR",
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
                title = "Combine two bit patterns",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = rs1, value = "0b010" },
                        { name = rs2, value = "0b011" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0xF0F0" },
                        { "register" = GPR, index = 3, value = "0x0FF0" },
                    ],
                watch = [R1, R2, R3],
            },
        ],
    notes = [],
    related = [],
}]
mapping clause encdec = OR(rd, rs1, rs2) <-> 0b01110 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Ors `rs1` and `rs2` into `rd`. */
function clause execute(OR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) | X(rs2)
}

union clause instruction = XOR : (regidx, regidx, regidx)
$[instruction_doc {
    title = "Bitwise exclusive OR",
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
                title = "Combine two bit patterns",
                operands =
                    [
                        { name = rd, value = "0b001" },
                        { name = rs1, value = "0b010" },
                        { name = rs2, value = "0b011" },
                    ],
                before =
                    [
                        { "register" = GPR, index = 2, value = "0xF0F0" },
                        { "register" = GPR, index = 3, value = "0x0FF0" },
                    ],
                watch = [R1, R2, R3],
            },
        ],
    notes = [],
    related = [],
}]
mapping clause encdec = XOR(rd, rs1, rs2) <-> 0b01111 : opcode @ rd @ rs1 @ rs2 @ ignored(2)
/*!
Exclusive-ors `rs1` and `rs2` into `rd`. */
function clause execute(XOR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) ^ X(rs2)
}

union clause instruction = NOT : (regidx, regidx)
$[instruction_doc {
    title = "Bitwise complement",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = write,
                description = "Destination register",
            },
            {
                name = rs,
                interpretation = "register",
                access = read,
                description = "Source register",
            },
        ],
    examples =
        [
            {
                title = "Invert every bit",
                operands = [{ name = rd, value = "0b001" }, { name = rs, value = "0b010" }],
                before = [{ "register" = GPR, index = 2, value = "0x00FF" }],
                watch = [R1, R2],
            },
        ],
    notes = [],
    related = [],
}]
mapping clause encdec = NOT(rd, rs) <-> 0b10000 : opcode @ rd @ rs @ ignored(5)
/*!
Complements `rs` into `rd`. */
function clause execute(NOT(rd, rs)) = {
    X(rd) = not_vec(X(rs))
}
