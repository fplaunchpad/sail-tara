/* Assembly syntax, as accepted by the TARA Studio assembler.
 * The immediates of LIL, LIH, SHL and SHR print unsigned; ADDI immediates and
 * all offsets print signed. Branch targets print as raw instruction offsets,
 * so assembling the text gives back the canonical encoding.
 */
$include "tara.sail"

function reg_name(r : regidx) -> string = concat_str("R", dec_str(unsigned(r)))

function operands1(mnemonic : string, a : string) -> string =
  concat_str(mnemonic, concat_str(" ", a))

function operands2(mnemonic : string, a : string, b : string) -> string =
  operands1(mnemonic, concat_str(a, concat_str(", ", b)))

function operands3(mnemonic : string, a : string, b : string, c : string) -> string =
  operands2(mnemonic, a, concat_str(b, concat_str(", ", c)))

function memory_operand(off : bits(5), base : regidx) -> string =
  concat_str(dec_str(signed(off)), concat_str("(", concat_str(reg_name(base), ")")))

val assembly : instruction -> string

function assembly(insn) = match insn {
  NOP() => "NOP",
  HLT() => "HLT",
  RET() => "RET",
  MOV(rd, rs) => operands2("MOV", reg_name(rd), reg_name(rs)),
  NOT(rd, rs) => operands2("NOT", reg_name(rd), reg_name(rs)),
  LIL(rd, imm) => operands2("LIL", reg_name(rd), dec_str(unsigned(imm))),
  LIH(rd, imm) => operands2("LIH", reg_name(rd), dec_str(unsigned(imm))),
  ADDI(rd, imm) => operands2("ADDI", reg_name(rd), dec_str(signed(imm))),
  SHL(rd, shamt) => operands2("SHL", reg_name(rd), dec_str(unsigned(shamt))),
  SHR(rd, shamt) => operands2("SHR", reg_name(rd), dec_str(unsigned(shamt))),
  LDW(rd, base, off) => operands2("LDW", reg_name(rd), memory_operand(off, base)),
  STW(rs, base, off) => operands2("STW", reg_name(rs), memory_operand(off, base)),
  LDB(rd, base, off) => operands2("LDB", reg_name(rd), memory_operand(off, base)),
  STB(rs, base, off) => operands2("STB", reg_name(rs), memory_operand(off, base)),
  ADD(rd, rs1, rs2) => operands3("ADD", reg_name(rd), reg_name(rs1), reg_name(rs2)),
  SUB(rd, rs1, rs2) => operands3("SUB", reg_name(rd), reg_name(rs1), reg_name(rs2)),
  MUL(rd, rs1, rs2) => operands3("MUL", reg_name(rd), reg_name(rs1), reg_name(rs2)),
  AND(rd, rs1, rs2) => operands3("AND", reg_name(rd), reg_name(rs1), reg_name(rs2)),
  OR(rd, rs1, rs2) => operands3("OR", reg_name(rd), reg_name(rs1), reg_name(rs2)),
  XOR(rd, rs1, rs2) => operands3("XOR", reg_name(rd), reg_name(rs1), reg_name(rs2)),
  SLT(rd, rs1, rs2) => operands3("SLT", reg_name(rd), reg_name(rs1), reg_name(rs2)),
  BZ(rs, off) => operands2("BZ", reg_name(rs), dec_str(signed(off))),
  BN(rs, off) => operands2("BN", reg_name(rs), dec_str(signed(off))),
  JMP(off) => operands1("JMP", dec_str(signed(off))),
  CALL(off) => operands1("CALL", dec_str(signed(off))),
  PUSH(rs) => operands1("PUSH", reg_name(rs)),
  POP(rd) => operands1("POP", reg_name(rd))
}
