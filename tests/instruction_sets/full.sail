/* An instruction set that assigns every opcode. Its decode still ends with the fallback, which
   the documentation plugin requires. */

default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
overload operator ^ = {concat_str}

type word = bits(4)

scattered union instruction
union clause instruction = ZERO : unit
union clause instruction = ONE : bits(3)
end instruction

val encode : instruction -> word
scattered function encode
function clause encode(ZERO()) = 0b0 @ 0b000
function clause encode(ONE(value)) = 0b1 @ value
end encode

val decode : word -> option(instruction)
scattered function decode
function clause decode(0b0 @ _ : bits(3)) = Some(ZERO())
function clause decode(0b1 @ value : bits(3)) = Some(ONE(value))
function clause decode(_) = None()
end decode

val assembly : instruction <-> string
scattered mapping assembly
mapping clause assembly = ZERO() <-> "zero"
mapping clause assembly = ONE(value) <-> "one " ^ dec_bits_3(value)
end assembly
