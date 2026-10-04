/* A 32-bit, three-register instruction set. */

default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
$include <hex_bits.sail>
overload operator ^ = {concat_str}

type word = bits(32)
type regidx = bits(5)

val ignored : forall 'n, 'n >= 0. int('n) <-> bits('n)
mapping ignored = { forwards width => sail_zeros(width), backwards bits => length(bits) }

scattered union instruction
union clause instruction = ADD : (regidx, regidx, regidx)
union clause instruction = LOAD : (regidx, regidx, bits(16))
union clause instruction = HALT : unit
end instruction

val encdec : instruction <-> word
scattered mapping encdec
mapping clause encdec = ADD(rd, rs, rt) <-> 0b000001 @ rd @ rs @ rt @ ignored(11)
mapping clause encdec = LOAD(rd, base, offset) <-> 0b000010 @ rd @ base @ offset
mapping clause encdec = HALT() <-> 0b111111 @ ignored(26)
end encdec

val execute : instruction -> unit
scattered function execute
function clause execute(ADD(_, _, _)) = ()
function clause execute(LOAD(_, _, _)) = ()
function clause execute(HALT()) = ()
end execute

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
