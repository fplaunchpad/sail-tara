/* An instruction set that assigns every opcode. */

default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
overload operator ^ = {concat_str}

type word = bits(4)

val ignored : forall 'n, 'n >= 0. int('n) <-> bits('n)
mapping ignored = { forwards width => sail_zeros(width), backwards bits => length(bits) }

scattered union instruction
union clause instruction = ZERO : unit
union clause instruction = ONE : bits(3)
end instruction

val encdec : instruction <-> word
scattered mapping encdec
mapping clause encdec = ZERO() <-> 0b0 @ ignored(3)
mapping clause encdec = ONE(value) <-> 0b1 @ value
end encdec

val execute : instruction -> unit
scattered function execute
function clause execute(ZERO()) = ()
function clause execute(ONE(_)) = ()
end execute

val assembly : instruction <-> string
scattered mapping assembly
mapping clause assembly = ZERO() <-> "zero"
mapping clause assembly = ONE(value) <-> "one " ^ dec_bits_3(value)
end assembly
