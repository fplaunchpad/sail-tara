/* Assembly syntax, as accepted by the TARA Studio assembler.
 * The immediates of LIL, LIH, SHL and SHR print unsigned; ADDI immediates and
 * all offsets print signed. Branch targets print as raw instruction offsets,
 * so assembling the text gives back the canonical encoding.
 */

$include "tara.sail"

/*! `assembly` prints an instruction in the syntax of the TARA Studio assembler. Registers print as
R0 to R7. The immediates of `LIL`, `LIH`, `SHL` and `SHR` print as unsigned decimal numbers; the
immediate of `ADDI` and all offsets print signed. A memory operand prints as `off(base)`. Branch and
jump targets print as raw signed instruction offsets, so assembling the text gives back the
canonical encoding. The Studio assembler also accepts a label in place of an offset. The file binds
`^` to string concatenation, as notation.
 */
$anchor syntax

overload operator ^ = {concat_str}

/*! The text of a register. */
function reg(r : regidx) -> string = "R" ^ dec_str(unsigned(r))

/*! The text of a memory operand: the signed offset, then the base register in parentheses. */
function mem(off : bits(5), base : regidx) -> string =
    dec_str(signed(off)) ^ "(" ^ reg(base) ^ ")"

/*! An instruction with one operand: the mnemonic, a space, the operand. */
function op1(mnemonic : string, a : string) -> string = mnemonic ^ " " ^ a

/*! An instruction with two operands, separated by a comma and a space. */
function op2(mnemonic : string, a : string, b : string) -> string =
    op1(mnemonic, a ^ ", " ^ b)

/*! An instruction with three operands, separated by commas and spaces. */
function op3(mnemonic : string, a : string, b : string, c : string) -> string =
    op2(mnemonic, a, b ^ ", " ^ c)

/*! Prints an instruction as assembly source. Each instruction has its clause of `assembly` next to
its other clauses.
 */
val assembly : instruction -> string
scattered function assembly

function clause assembly(NOP()) = "NOP"
function clause assembly(HLT()) = "HLT"
function clause assembly(MOV(rd, rs)) = op2("MOV", reg(rd), reg(rs))
function clause assembly(LIL(rd, imm)) = op2("LIL", reg(rd), dec_str(unsigned(imm)))
function clause assembly(LIH(rd, imm)) = op2("LIH", reg(rd), dec_str(unsigned(imm)))
function clause assembly(LDW(rd, base, off)) = op2("LDW", reg(rd), mem(off, base))
function clause assembly(STW(rs, base, off)) = op2("STW", reg(rs), mem(off, base))
function clause assembly(LDB(rd, base, off)) = op2("LDB", reg(rd), mem(off, base))
function clause assembly(STB(rs, base, off)) = op2("STB", reg(rs), mem(off, base))
function clause assembly(ADD(rd, rs1, rs2)) = op3("ADD", reg(rd), reg(rs1), reg(rs2))
function clause assembly(SUB(rd, rs1, rs2)) = op3("SUB", reg(rd), reg(rs1), reg(rs2))
function clause assembly(ADDI(rd, imm)) = op2("ADDI", reg(rd), dec_str(signed(imm)))
function clause assembly(MUL(rd, rs1, rs2)) = op3("MUL", reg(rd), reg(rs1), reg(rs2))
function clause assembly(AND(rd, rs1, rs2)) = op3("AND", reg(rd), reg(rs1), reg(rs2))
function clause assembly(OR(rd, rs1, rs2)) = op3("OR", reg(rd), reg(rs1), reg(rs2))
function clause assembly(XOR(rd, rs1, rs2)) = op3("XOR", reg(rd), reg(rs1), reg(rs2))
function clause assembly(NOT(rd, rs)) = op2("NOT", reg(rd), reg(rs))
function clause assembly(SHL(rd, shamt)) = op2("SHL", reg(rd), dec_str(unsigned(shamt)))
function clause assembly(SHR(rd, shamt)) = op2("SHR", reg(rd), dec_str(unsigned(shamt)))
function clause assembly(SLT(rd, rs1, rs2)) = op3("SLT", reg(rd), reg(rs1), reg(rs2))
function clause assembly(BZ(rs, off)) = op2("BZ", reg(rs), dec_str(signed(off)))
function clause assembly(BN(rs, off)) = op2("BN", reg(rs), dec_str(signed(off)))
function clause assembly(JMP(off)) = op1("JMP", dec_str(signed(off)))
function clause assembly(CALL(off)) = op1("CALL", dec_str(signed(off)))
function clause assembly(RET()) = "RET"
function clause assembly(PUSH(rs)) = op1("PUSH", reg(rs))
function clause assembly(POP(rd)) = op1("POP", reg(rd))

end assembly
