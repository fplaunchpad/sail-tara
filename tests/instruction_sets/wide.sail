/* A 32-bit, three-register instruction set. */

default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
$include <hex_bits.sail>
overload operator ^ = {concat_str}

type word = bits(32)
type regidx = bits(5)

scattered union instruction
union clause instruction = ADD : (regidx, regidx, regidx)
union clause instruction = LOAD : (regidx, regidx, bits(16))
union clause instruction = HALT : unit
end instruction

val encode : instruction -> word
scattered function encode
function clause encode(ADD(rd, rs, rt)) = 0b000001 @ rd @ rs @ rt @ 0b00000000000
function clause encode(LOAD(rd, base, offset)) = 0b000010 @ rd @ base @ offset
function clause encode(HALT()) = 0b111111 @ 0b00000000000000000000000000
end encode

val decode : word -> option(instruction)
scattered function decode
function clause decode(0b000001 @ rd : regidx @ rs : regidx @ rt : regidx @ _ : bits(11)) =
  Some(ADD(rd, rs, rt))
function clause decode(0b000010 @ rd : regidx @ base : regidx @ offset : bits(16)) =
  Some(LOAD(rd, base, offset))
function clause decode(0b111111 @ _ : bits(26)) = Some(HALT())
function clause decode(_) = None()
end decode

mapping reg_name : regidx <-> string = {
  forwards value => "r" ^ dec_bits_5(value),
  backwards _ if false => 0b00000
}

val assembly : instruction <-> string
scattered mapping assembly
mapping clause assembly =
  ADD(rd, rs, rt) <-> "add " ^ reg_name(rd) ^ ", " ^ reg_name(rs) ^ ", " ^ reg_name(rt)
mapping clause assembly =
  LOAD(rd, base, offset) <->
    "load " ^ reg_name(rd) ^ ", " ^ hex_bits_16(offset) ^ "(" ^ reg_name(base) ^ ")"
mapping clause assembly = HALT() <-> "halt"
end assembly
