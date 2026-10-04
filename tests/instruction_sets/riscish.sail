/* A 32-bit instruction set laid out like RISC-V: the opcode in the low bits, fixed bits in the
   middle too, instructions that share an opcode, anchors between instructions, and functions
   named neither encode nor execute. */

default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
$include <hex_bits.sail>
overload operator ^ = {concat_str}

type word = bits(32)
type regidx = bits(5)

scattered union instruction

/*!
=== Register arithmetic */
$anchor register_arithmetic

union clause instruction = ADD : (regidx, regidx, regidx)
union clause instruction = SUB : (regidx, regidx, regidx)

/*!
=== Loads */
$anchor loads

union clause instruction = LW : (regidx, regidx, bits(12))

end instruction

val decode : word -> option(instruction)
scattered function decode
function clause decode((0b0000000 as funct7) @ rs2 : regidx @ rs1 : regidx @ (0b000 as funct3)
                       @ rd : regidx @ 0b0110011) = Some(ADD(rd, rs1, rs2))
function clause decode((0b0100000 as funct7) @ rs2 : regidx @ rs1 : regidx @ (0b000 as funct3)
                       @ rd : regidx @ 0b0110011) = Some(SUB(rd, rs1, rs2))
function clause decode(imm : bits(12) @ rs1 : regidx @ (0b010 as funct3) @ rd : regidx
                       @ 0b0000011) = Some(LW(rd, rs1, imm))
function clause decode(_) = None()
end decode

val semantics : instruction -> unit
scattered function semantics
/*!
Adds `rs1` and `rs2` into `rd`. */
function clause semantics(ADD(rd, rs1, rs2)) = ()
function clause semantics(SUB(rd, rs1, rs2)) = ()
function clause semantics(LW(rd, rs1, imm)) = ()
end semantics

mapping reg_name : regidx <-> string = {
  forwards value => "x" ^ dec_bits_5(value),
  backwards _ if false => 0b00000
}

val assembly : instruction <-> string
scattered mapping assembly
mapping clause assembly =
  ADD(rd, rs1, rs2) <-> "add " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly =
  SUB(rd, rs1, rs2) <-> "sub " ^ reg_name(rd) ^ ", " ^ reg_name(rs1) ^ ", " ^ reg_name(rs2)
mapping clause assembly =
  LW(rd, rs1, imm) <-> "lw " ^ reg_name(rd) ^ ", " ^ hex_bits_12(imm) ^ "(" ^ reg_name(rs1) ^ ")"
end assembly
