/* Assembly syntax, as accepted by the TARA Studio assembler.
 * The immediates of LIL, LIH, SHL and SHR print unsigned; ADDI immediates and
 * all offsets print signed. Branch targets print as raw instruction offsets,
 * so assembling the text gives back the canonical encoding.
 */
$include "tara.sail"

overload operator ^ = {concat_str}

function reg(r : regidx) -> string = "R" ^ dec_str(unsigned(r))

function mem(off : bits(5), base : regidx) -> string =
  dec_str(signed(off)) ^ "(" ^ reg(base) ^ ")"

function op1(mnemonic : string, a : string) -> string = mnemonic ^ " " ^ a

function op2(mnemonic : string, a : string, b : string) -> string =
  op1(mnemonic, a ^ ", " ^ b)

function op3(mnemonic : string, a : string, b : string, c : string) -> string =
  op2(mnemonic, a, b ^ ", " ^ c)

val assembly : instruction -> string

function assembly(insn) = match insn {
  NOP() => "NOP",
  HLT() => "HLT",
  RET() => "RET",
  MOV(rd, rs) => op2("MOV", reg(rd), reg(rs)),
  NOT(rd, rs) => op2("NOT", reg(rd), reg(rs)),
  LIL(rd, imm) => op2("LIL", reg(rd), dec_str(unsigned(imm))),
  LIH(rd, imm) => op2("LIH", reg(rd), dec_str(unsigned(imm))),
  ADDI(rd, imm) => op2("ADDI", reg(rd), dec_str(signed(imm))),
  SHL(rd, shamt) => op2("SHL", reg(rd), dec_str(unsigned(shamt))),
  SHR(rd, shamt) => op2("SHR", reg(rd), dec_str(unsigned(shamt))),
  LDW(rd, base, off) => op2("LDW", reg(rd), mem(off, base)),
  STW(rs, base, off) => op2("STW", reg(rs), mem(off, base)),
  LDB(rd, base, off) => op2("LDB", reg(rd), mem(off, base)),
  STB(rs, base, off) => op2("STB", reg(rs), mem(off, base)),
  ADD(rd, rs1, rs2) => op3("ADD", reg(rd), reg(rs1), reg(rs2)),
  SUB(rd, rs1, rs2) => op3("SUB", reg(rd), reg(rs1), reg(rs2)),
  MUL(rd, rs1, rs2) => op3("MUL", reg(rd), reg(rs1), reg(rs2)),
  AND(rd, rs1, rs2) => op3("AND", reg(rd), reg(rs1), reg(rs2)),
  OR(rd, rs1, rs2) => op3("OR", reg(rd), reg(rs1), reg(rs2)),
  XOR(rd, rs1, rs2) => op3("XOR", reg(rd), reg(rs1), reg(rs2)),
  SLT(rd, rs1, rs2) => op3("SLT", reg(rd), reg(rs1), reg(rs2)),
  BZ(rs, off) => op2("BZ", reg(rs), dec_str(signed(off))),
  BN(rs, off) => op2("BN", reg(rs), dec_str(signed(off))),
  JMP(off) => op1("JMP", dec_str(signed(off))),
  CALL(off) => op1("CALL", dec_str(signed(off))),
  PUSH(rs) => op1("PUSH", reg(rs)),
  POP(rd) => op1("POP", reg(rd))
}
