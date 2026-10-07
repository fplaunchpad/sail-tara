/*!
=== Data movement */
$anchor section_data_movement

/*!
`NOP` and `HLT` take no operands. `MOV` copies a register, and `LIL` and `LIH` load a 16-bit
constant a byte at a time.
 */
$anchor data_movement

union clause instruction = NOP : unit
$[instruction_doc {
    title = "No operation",
    operands = [],
    examples =
        [{ title = "Advance without changing registers", operands = [], before = [], watch = [] }],
    notes = [],
    related = [],
}]
mapping clause encdec = NOP() <-> 0b00000 : opcode @ ignored(11)
/*!
Does nothing. PC moves on to the next instruction. */
function clause execute(NOP()) = ()

union clause instruction = HLT : unit
$[instruction_doc {
    title = Halt,
    operands = [],
    examples = [{ title = "Retire and halt", operands = [], before = [], watch = [] }],
    notes =
        [
            {
                category = architecture,
                text = "HLT retires and advances PC before subsequent driver calls return Stopped.",
            },
        ],
    related = [],
}]
mapping clause encdec = HLT() <-> 0b00001 : opcode @ ignored(11)
/*!
Sets the halt latch. `HLT` retires, so PC moves past it; from then on `step` and `run_instruction`
return `Stopped` until `reset`.
 */
function clause execute(HLT()) = {
    HALTED = true
}

union clause instruction = MOV : (regidx, regidx)
$[instruction_doc {
    title = "Move register",
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
                title = "Copy a register",
                operands = [{ name = rd, value = "0b001" }, { name = rs, value = "0b010" }],
                before = [{ "register" = GPR, index = 2, value = "0x1234" }],
                watch = [R1, R2],
            },
        ],
    notes = [],
    related = [],
}]
mapping clause encdec = MOV(rd, rs) <-> 0b00010 : opcode @ rd @ rs @ ignored(5)
/*!
Copies `rs` to `rd`. */
function clause execute(MOV(rd, rs)) = {
    X(rd) = X(rs)
}

union clause instruction = LIL : (regidx, bits(8))
$[instruction_doc {
    title = "Load low immediate",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = write,
                description = "Destination register",
            },
            {
                name = imm,
                interpretation = unsigned,
                access = value,
                description = "Immediate value",
            },
        ],
    examples =
        [
            {
                title = "Replace the low byte",
                operands = [{ name = rd, value = "0b001" }, { name = imm, value = "0xAB" }],
                before = [{ "register" = GPR, index = 1, value = "0x1200" }],
                watch = [R1],
            },
        ],
    notes = [{ category = architecture, text = "The high byte is cleared." }],
    related = [LIH],
}]
mapping clause encdec = LIL(rd, imm) <-> 0b00011 : opcode @ rd @ imm
/*!
Sets `rd` to the immediate, zero-extended. */
function clause execute(LIL(rd, imm)) = {
    X(rd) = 0x00 @ imm
}

union clause instruction = LIH : (regidx, bits(8))
$[instruction_doc {
    title = "Load high immediate",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = read_write,
                description = "Destination register",
            },
            {
                name = imm,
                interpretation = unsigned,
                access = value,
                description = "Immediate value",
            },
        ],
    examples =
        [
            {
                title = "Preserve the low byte",
                operands = [{ name = rd, value = "0b001" }, { name = imm, value = "0xAB" }],
                before = [{ "register" = GPR, index = 1, value = "0x0034" }],
                watch = [R1],
            },
        ],
    notes = [{ category = architecture, text = "The low byte of the destination is preserved." }],
    related = [LIL],
}]
mapping clause encdec = LIH(rd, imm) <-> 0b00100 : opcode @ rd @ imm
/*!
Replaces the upper byte of `rd` with the immediate. After a `LIL`, it completes a 16-bit constant.
 */
function clause execute(LIH(rd, imm)) = {
    X(rd) = imm @ X(rd)[7 .. 0]
}
