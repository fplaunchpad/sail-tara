/*!
=== Stack */
$anchor section_stack

/*!
The stack grows down from the address in R7, a word at a time, unchecked. Reset leaves R7 alone, so
a program sets it before its first `PUSH`. Each instruction takes its two steps in the order of the
ISA table, which shows when the register is R7 itself.
 */
$anchor stack

union clause instruction = PUSH : regidx
$[instruction_doc {
    title = "Push register",
    operands = [{ name = rs, interpretation = "register", access = read, description = Source }],
    examples =
        [
            {
                title = "Push one word",
                operands = [{ name = rs, value = "0b001" }],
                before =
                    [
                        { "register" = GPR, index = 1, value = "0x1234" },
                        { "register" = GPR, index = 7, value = "0x0402" },
                    ],
                watch = [R1],
            },
            {
                title = "Push the stack pointer itself",
                operands = [{ name = rs, value = "0b111" }],
                before = [{ "register" = GPR, index = 7, value = "0x0402" }],
                watch = [R7],
            },
        ],
    notes =
        [
            {
                category = architecture,
                text = "The stack grows down through R7 without bounds checks.",
            },
            {
                category = assumption,
                text =
                    """
                    PUSH R7 stores the decremented stack pointer, following the order of the
                                        operations.
                    """,
            },
        ],
    related = [POP],
}]
mapping clause encdec = PUSH(rs) <-> 0b11001 : opcode @ rs @ ignored(8)
/*!
Decrements R7 by 2, then stores `rs` at the address in R7, so `PUSH R7` stores the decremented
value.
 */
function clause execute(PUSH(rs)) = {
    X(sp) = X(sp) - 0x0002;
    write_word(X(sp), X(rs))
}

union clause instruction = POP : regidx
$[instruction_doc {
    title = "Pop register",
    operands =
        [
            {
                name = rd,
                interpretation = "register",
                access = write,
                description = "Destination register",
            },
        ],
    examples =
        [
            {
                title = "Pop one word",
                operands = [{ name = rd, value = "0b001" }],
                before =
                    [
                        { "register" = GPR, index = 7, value = "0x0400" },
                        { "register" = MEM, index = 1024, value = "0x12" },
                        { "register" = MEM, index = 1025, value = "0x34" },
                    ],
                watch = [R1],
            },
            {
                title = "Pop into the stack pointer",
                operands = [{ name = rd, value = "0b111" }],
                before =
                    [
                        { "register" = GPR, index = 7, value = "0x0400" },
                        { "register" = MEM, index = 1024, value = "0x05" },
                        { "register" = MEM, index = 1025, value = "0x00" },
                    ],
                watch = [R7],
            },
        ],
    notes =
        [
            {
                category = assumption,
                text = "POP R7 increments the loaded value, leaving that value plus two in R7.",
            },
        ],
    related = [PUSH],
}]
mapping clause encdec = POP(rd) <-> 0b11010 : opcode @ rd @ ignored(8)
/*!
Loads the word at the address in R7 into `rd`, then increments R7 by 2, so `POP R7` leaves the
loaded value plus 2.
 */
function clause execute(POP(rd)) = {
    X(rd) = read_word(X(sp));
    X(sp) = X(sp) + 0x0002
}
