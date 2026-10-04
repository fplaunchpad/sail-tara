/* A 12-bit instruction set whose assembly syntax needs constants and helper mappings. */

default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
overload operator ^ = {concat_str}

type word = bits(12)

val ignored : forall 'n, 'n >= 0. int('n) <-> bits('n)
mapping ignored = { forwards width => sail_zeros(width), backwards bits => length(bits) }

scattered union instruction
union clause instruction = Tiny : (bits(2), bits(3))
union clause instruction = Stop : unit
end instruction

val encdec : instruction <-> word
scattered mapping encdec
mapping clause encdec = Tiny(first, second) <-> 0x2 @ first @ second @ ignored(3)
mapping clause encdec = Stop() <-> 0x1 @ ignored(8)
end encdec

val execute : instruction -> unit
scattered function execute
function clause execute(Tiny(_, _)) = ()
function clause execute(Stop()) = ()
end execute

mapping separator : unit <-> string = { () <-> ":" }
mapping repeat_operand : bits(3) <-> string = {
  forwards value => dec_bits_3(value) ^ "/" ^ dec_bits_3(value),
  backwards _ if false => 0b000
}

val assembly : instruction <-> string
scattered mapping assembly
mapping clause assembly = Stop() <-> "STOP"
mapping clause assembly =
  Tiny(second, first) <-> "TINY" ^ separator() ^ repeat_operand(first) ^ "/" ^ dec_bits_2(second)
end assembly
