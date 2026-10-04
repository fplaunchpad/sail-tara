/* Assembly syntax, as accepted by the TARA Studio assembler.
 * The immediates of LIL, LIH, SHL and SHR print unsigned; ADDI immediates and
 * all offsets print signed. Branch targets print as raw instruction offsets,
 * so assembling the text gives back the canonical encoding.
 */

$include "tara.sail"
$include <mapping.sail>
$include <dec_bits.sail>

/*!
== Assembly syntax */
$anchor section_assembly

/*!
`assembly` prints an instruction in the syntax of the TARA Studio assembler. Registers print as
R0 to R7. The immediates of `LIL`, `LIH`, `SHL` and `SHR` print as unsigned decimal numbers; the
immediate of `ADDI` and all offsets print signed. A memory operand prints as `off(base)`. Branch and
jump targets print as raw signed instruction offsets, so assembling the text gives back the
canonical encoding. The Studio assembler also accepts a label in place of an offset. The file binds
`^` to string concatenation, as notation.
 */
$anchor syntax

overload operator ^ = {concat_str}

/*!
A register name, shared with the assembly mapping. */
mapping reg_name : regidx <-> string = { r <-> "R" ^ dec_bits_3(r) }

/*!
Unsigned decimal operands. */
mapping unsigned_dec_8 : bits(8) <-> string = { bits <-> dec_bits_8(bits) }

/*!
Internal decimal printers used by the assembly mapping and its generated documentation tables.
The reverse clauses never match: these helpers do not parse assembly. Explicit reverse clauses
avoid empty matches in Sail 0.20.3's OCaml output for forward-only mappings.
 */
mapping signed_dec_5 : bits(5) <-> string = {
  forwards bits => dec_str(signed(bits)),
  backwards _ if false => 0b00000
}
mapping signed_dec_8 : bits(8) <-> string = {
  forwards bits => dec_str(signed(bits)),
  backwards _ if false => 0b00000000
}
mapping signed_dec_11 : bits(11) <-> string = {
  forwards bits => dec_str(signed(bits)),
  backwards _ if false => 0b00000000000
}

/*!
The native instruction-to-string mapping used to print assembly source.
 */
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
