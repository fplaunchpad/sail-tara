/*!
=== Control flow */
$anchor section_control_flow

/*!
A relative target is `PC + 2 + 2 * off`: the offset counts instructions from the next one. PC keeps
11 bits, so targets wrap around memory.
 */
$anchor control_flow

union clause instruction = BZ : (regidx, bits(8))
$[instruction_doc {
    title = "Branch if zero",
    operands =
        [
            {
                name = rs,
                interpretation = "register",
                access = read,
                description = "Source register",
            },
            {
                name = off,
                interpretation = signed,
                access = value,
                description = "Relative displacement",
                unit = instructions,
            },
        ],
    examples =
        [
            {
                title = "Take the branch",
                operands = [{ name = rs, value = "0b010" }, { name = off, value = "0xFF" }],
                before = [{ "register" = GPR, index = 2, value = "0x0000" }],
                watch = [R2],
            },
            {
                title = "Leave the branch untaken",
                operands = [{ name = rs, value = "0b010" }, { name = off, value = "0xFF" }],
                before = [{ "register" = GPR, index = 2, value = "0x0001" }],
                watch = [R2],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    """
                    The offset counts instructions from PC + 2. Relative targets wrap to the low
                                        11 bits.
                    """,
            },
        ],
    related = [BN, SLT],
}]
mapping clause encdec = BZ(rs, off) <-> 0b10100 : opcode @ rs @ off
/*!
Branches if `rs` is zero, by -128 to 127 instructions. */
function clause execute(BZ(rs, off)) = {
    if X(rs) == 0x0000 then {
        nextPC = PC + 0x0002 + 2 * signed(off)
    }
}

union clause instruction = BN : (regidx, bits(8))
$[instruction_doc {
    title = "Branch if negative",
    operands =
        [
            {
                name = rs,
                interpretation = "register",
                access = read,
                description = "Source register",
            },
            {
                name = off,
                interpretation = signed,
                access = value,
                description = "Relative displacement",
                unit = instructions,
            },
        ],
    examples =
        [
            {
                title = "Take the branch",
                operands = [{ name = rs, value = "0b010" }, { name = off, value = "0xFD" }],
                before = [{ "register" = GPR, index = 2, value = "0x8000" }],
                watch = [R2],
            },
            {
                title = "Leave the branch untaken",
                operands = [{ name = rs, value = "0b010" }, { name = off, value = "0xFD" }],
                before = [{ "register" = GPR, index = 2, value = "0x0001" }],
                watch = [R2],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    """
                    The offset counts instructions from PC + 2. Relative targets wrap to the low
                                        11 bits.
                    """,
            },
        ],
    related = [BZ, SLT],
}]
mapping clause encdec = BN(rs, off) <-> 0b10101 : opcode @ rs @ off
/*!
Branches if `rs` is negative, that is, if its bit 15 is set. */
function clause execute(BN(rs, off)) = {
    if X(rs)[15] == bitone then {
        nextPC = PC + 0x0002 + 2 * signed(off)
    }
}

union clause instruction = JMP : bits(11)
$[instruction_doc {
    title = "Relative jump",
    operands =
        [
            {
                name = off,
                interpretation = signed,
                access = value,
                description = "Relative displacement",
                unit = instructions,
            },
        ],
    examples =
        [
            {
                title = "Jump back to this instruction",
                operands = [{ name = off, value = "0b11111111111" }],
                before = [],
                watch = [],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text =
                    """
                    The offset counts instructions from PC + 2. Relative targets wrap to the low
                                        11 bits.
                    """,
            },
        ],
    related = [],
}]
mapping clause encdec = JMP(off) <-> 0b10110 : opcode @ off
/*!
Jumps by -1024 to 1023 instructions, which reaches all of memory. */
function clause execute(JMP(off)) = {
    nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = CALL : bits(11)
$[instruction_doc {
    title = "Call subroutine",
    operands =
        [
            {
                name = off,
                interpretation = signed,
                access = value,
                description = "Relative displacement",
                unit = instructions,
            },
        ],
    examples =
        [
            {
                title = "Wrap the link and target",
                operands = [{ name = off, value = "0b00000000000" }],
                before = [{ "register" = PC, value = "0x07FE" }],
                watch = [R6],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text = "R6 receives the masked address of the next instruction.",
            },
            {
                category = architecture,
                text =
                    """
                    The offset counts instructions from PC + 2. Relative targets wrap to the low
                                        11 bits.
                    """,
            },
        ],
    related = [RET],
}]
mapping clause encdec = CALL(off) <-> 0b10111 : opcode @ off
/*!
Writes the return address, that of the next instruction, to R6 and jumps like `JMP`. It touches
neither R7 nor memory.
 */
function clause execute(CALL(off)) = {
    X(lr) = pc_mask(PC + 0x0002);
    nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = RET : unit
$[instruction_doc {
    title = "Return from subroutine",
    operands = [],
    examples =
        [
            {
                title = "Return to an odd address",
                operands = [],
                before = [{ "register" = GPR, index = 6, value = "0x0201" }],
                watch = [],
            },
        ],
    notes = [{ category = architecture, text = "Low 11 bits of R6 become PC, preserving bit 0." }],
    related = [CALL],
}]
mapping clause encdec = RET() <-> 0b11000 : opcode @ ignored(11)
/*!
Jumps to the address in R6. */
function clause execute(RET()) = {
    nextPC = X(lr)
}
