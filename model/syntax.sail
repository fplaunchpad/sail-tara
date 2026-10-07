/* Assembly syntax, as the TARA Studio assembler reads it. */

$include "tara.sail"
$include <mapping.sail>
$include <dec_bits.sail>

/*!
@anchor section_assembly
== Assembly syntax

@anchor syntax
`assembly` prints an instruction in the syntax of the TARA Studio assembler, and assembling the text
gives back the instruction's word, with zeros for padding. Registers print as `R0` to `R7` and a
memory operand as `off(base)`. The immediates of `LIL`, `LIH`, `SHL` and `SHR` print unsigned, and
the immediate of `ADDI` and every offset signed. Branch and jump offsets print as numbers of
instructions, where the assembler also accepts labels.
 */
overload operator ^ = {concat_str}

/*!
@brief Print a register name

A register's name, `R0` to `R7`.
 */
mapping reg_name : regidx <-> string = { r <-> "R" ^ dec_bits_3(r) }

/*!
@brief Print an unsigned byte

An unsigned byte, in decimal.
 */
mapping unsigned_dec_8 : bits(8) <-> string = { bits <-> dec_bits_8(bits) }

/*!
@brief Print a signed five-bit value

Signed numbers, in decimal. They only print: their reverse clauses never match, and exist because
Sail 0.20.3's OCaml backend mishandles mappings that only go forwards.
 */
mapping signed_dec_5 : bits(5) <-> string = {
  forwards bits => dec_str(signed(bits)),
  backwards _ if false => 0b00000
}

/*!
@brief Print a signed byte
 */
mapping signed_dec_8 : bits(8) <-> string = {
  forwards bits => dec_str(signed(bits)),
  backwards _ if false => 0b00000000
}

/*!
@brief Print a signed eleven-bit value
 */
mapping signed_dec_11 : bits(11) <-> string = {
  forwards bits => dec_str(signed(bits)),
  backwards _ if false => 0b00000000000
}

/*!
An instruction's assembly text. */
val assembly : instruction <-> string
scattered mapping assembly

mapping clause assembly = NOP() <-> "NOP"
mapping clause assembly = HLT() <-> "HLT"
mapping clause assembly = MOV(rd, rs) <-> "MOV " ^ reg_name(rd) ^ ", " ^ reg_name(rs)
mapping clause assembly = LIL(rd, imm) <-> "LIL " ^ reg_name(rd) ^ ", " ^ unsigned_dec_8(imm)
mapping clause assembly = LIH(rd, imm) <-> "LIH " ^ reg_name(rd) ^ ", " ^ unsigned_dec_8(imm)
mapping clause assembly =
  LDW(rd, base, off) <->
    "LDW " ^ reg_name(rd) ^ ", " ^ signed_dec_5(off) ^ "(" ^ reg_name(base) ^ ")"
mapping clause assembly =
  STW(rs, base, off) <->
    "STW " ^ reg_name(rs) ^ ", " ^ signed_dec_5(off) ^ "(" ^ reg_name(base) ^ ")"
mapping clause assembly =
  LDB(rd, base, off) <->
    "LDB " ^ reg_name(rd) ^ ", " ^ signed_dec_5(off) ^ "(" ^ reg_name(base) ^ ")"
mapping clause assembly =
  STB(rs, base, off) <->
    "STB " ^ reg_name(rs) ^ ", " ^ signed_dec_5(off) ^ "(" ^ reg_name(base) ^ ")"
mapping clause assembly =
  ADD(rd, rs1, rs2) <-> "ADD " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly =
  SUB(rd, rs1, rs2) <-> "SUB " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly = ADDI(rd, imm) <-> "ADDI " ^ reg_name(rd) ^ ", " ^ signed_dec_8(imm)
mapping clause assembly =
  MUL(rd, rs1, rs2) <-> "MUL " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly =
  AND(rd, rs1, rs2) <-> "AND " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly =
  OR(rd, rs1, rs2) <-> "OR " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly =
  XOR(rd, rs1, rs2) <-> "XOR " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly = NOT(rd, rs) <-> "NOT " ^ reg_name(rd) ^ ", " ^ reg_name(rs)
mapping clause assembly =
  SHL(rd, shamt) <-> "SHL " ^ reg_name(rd) ^ ", " ^ unsigned_dec_8(shamt)
mapping clause assembly =
  SHR(rd, shamt) <-> "SHR " ^ reg_name(rd) ^ ", " ^ unsigned_dec_8(shamt)
mapping clause assembly =
  SLT(rd, rs1, rs2) <-> "SLT " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly = BZ(rs, off) <-> "BZ " ^ reg_name(rs) ^ ", " ^ signed_dec_8(off)
mapping clause assembly = BN(rs, off) <-> "BN " ^ reg_name(rs) ^ ", " ^ signed_dec_8(off)
mapping clause assembly = JMP(off) <-> "JMP " ^ signed_dec_11(off)
mapping clause assembly = CALL(off) <-> "CALL " ^ signed_dec_11(off)
mapping clause assembly = RET() <-> "RET"
mapping clause assembly = PUSH(rs) <-> "PUSH " ^ reg_name(rs)
mapping clause assembly = POP(rd) <-> "POP " ^ reg_name(rd)

end assembly
