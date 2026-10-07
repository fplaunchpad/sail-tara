/* A 32-bit instruction set laid out like RISC-V: the opcode in the low bits, fixed bits in the
   middle too, a constructor that stands for two instructions, a guarded encoding, and anchors
   between instructions. */

default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
$include <hex_bits.sail>
overload operator ^ = {concat_str}
overload operator - = {sub_bits}

type word = bits(32)
type regidx = bits(5)
type opcode = bits(7)
type funct3 = bits(3)
type funct7 = bits(7)

enum rop = {RISCV_ADD, RISCV_SUB}

$[notation "x[{0}]"]
val X : regidx -> word
$[notation "x[{0}] = {1}"]
val set_X : (regidx, word) -> unit
$[notation "M[{0}][31:0]"]
val load : word -> word

scattered union instruction

/*!
=== Register arithmetic */
$anchor register_arithmetic

union clause instruction = RTYPE : (regidx, regidx, regidx, rop)

/*!
=== Loads and shifts */
$anchor loads

union clause instruction = LW : (bits(12), regidx, regidx)
union clause instruction = SLLI : (bits(6), regidx, regidx)

end instruction

val encdec : instruction <-> word
scattered mapping encdec
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_ADD)
  <-> 0b0000000 : funct7 @ rs2 @ rs1 @ 0b000 : funct3 @ rd @ 0b0110011 : opcode
mapping clause encdec = RTYPE(rs2, rs1, rd, RISCV_SUB)
  <-> 0b0100000 : funct7 @ rs2 @ rs1 @ 0b000 : funct3 @ rd @ 0b0110011 : opcode
mapping clause encdec = LW(imm, rs1, rd) <-> imm @ rs1 @ 0b010 : funct3 @ rd @ 0b0000011 : opcode
mapping clause encdec = SLLI(shamt, rs1, rd) if shamt[5] == bitzero
  <-> 0b000000 @ shamt @ rs1 @ 0b001 : funct3 @ rd @ 0b0010011 : opcode if shamt[5] == bitzero
end encdec

val execute : instruction -> unit
scattered function execute
/*!
Adds `rs1` and `rs2` into `rd`. */
function clause execute(RTYPE(rs2, rs1, rd, RISCV_ADD)) = set_X(rd, X(rs1) + X(rs2))
function clause execute(RTYPE(rs2, rs1, rd, RISCV_SUB)) = set_X(rd, X(rs1) - X(rs2))
function clause execute(LW(imm, rs1, rd)) = {
  let address = X(rs1) + sail_sign_extend(imm, 32);
  set_X(rd, load(address))
}
function clause execute(SLLI(shamt, rs1, rd)) = set_X(rd, sail_shiftleft(X(rs1), unsigned(shamt)))
end execute

mapping rtype_mnemonic : rop <-> string = { RISCV_ADD <-> "add", RISCV_SUB <-> "sub" }

mapping reg_name : regidx <-> string = {
  forwards value => "x" ^ dec_bits_5(value),
  backwards _ if false => 0b00000
}

val assembly : instruction <-> string
scattered mapping assembly
mapping clause assembly = RTYPE(rs2, rs1, rd, op)
  <-> rtype_mnemonic(op) ^ " " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly =
  LW(imm, rs1, rd) <-> "lw " ^ reg_name(rd) ^ ", " ^ hex_bits_12(imm) ^ "(" ^ reg_name(rs1) ^ ")"
mapping clause assembly = SLLI(shamt, rs1, rd)
  <-> "slli " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ hex_bits_6(shamt)
end assembly
