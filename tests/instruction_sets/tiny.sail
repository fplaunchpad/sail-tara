/* A 12-bit instruction set whose assembly syntax needs constants and helper mappings. */

default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
overload operator ^ = {concat_str}

type word = bits(12)

scattered union instruction
union clause instruction = Tiny : (bits(2), bits(3))
union clause instruction = Stop : unit
end instruction

val encode : instruction -> word
scattered function encode
function clause encode(Tiny(first, second)) = 0x2 @ first @ second @ 0b000
function clause encode(Stop()) = 0x1 @ 0b00000000
end encode

val decode : word -> option(instruction)
scattered function decode
function clause decode(0x2 @ first : bits(2) @ second : bits(3) @ _ : bits(3)) =
  Some(Tiny(first, second))
function clause decode(0x1 @ _ : bits(8)) = Some(Stop())
function clause decode(_) = None()
end decode

mapping separator : unit <-> string = { () <-> ":" }
mapping repeat_operand : bits(3) <-> string = {
  forwards value => dec_bits_3(value) ^ "/" ^ dec_bits_3(value),
  backwards _ if false => 0b000
}

val assembly : instruction <-> string
scattered mapping assembly
mapping clause assembly = Stop() <-> "STOP"
mapping clause assembly = Tiny(second, first) <-> "TINY" ^ separator() ^ repeat_operand(first) ^ "/" ^ dec_bits_2(second)
end assembly
