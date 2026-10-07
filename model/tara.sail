/* TARA's instructions. Each instruction's operands, encoding and effect sit together in the file
 * of its group under instructions/; the drivers in step.sail run them.
 */

$ifndef _TARA_SAIL
$define _TARA_SAIL
$include "machine.sail"

/*!
@anchor section_instruction_set
== The instruction set

@anchor encoding
An instruction is one word: a 5-bit opcode in bits 15 to 11, then its operand fields. `encdec` maps
each instruction to its word and back. Bits that no field uses are ignored: encoding writes them as
zeros and decoding accepts any value, so several words can decode to the same instruction. The
formats group the instructions by the names and widths of their fields.
 */
/* The bits that tell the instructions apart; encodings name them by annotating them. */
type opcode = bits(5)

/*!
@brief Ignore encoding bits

@anchor section_instruction_formats
`width` bits that decoding ignores: encoding writes them as zeros, and decoding accepts any
value.
 */
val ignored : forall 'n, 'n >= 0. int('n) <-> bits('n)

mapping ignored = {
    forwards width => sail_zeros(width),
    backwards bits => length(bits),
}

/*!
=== Instruction formats

@anchor section_opcodes
=== Opcodes

Opcodes 27 to 31 are unassigned: no clause of `encdec` matches their words, and `step` reports them
as `Illegal`. Operations use compact notation: fixed-width arithmetic wraps implicitly,
`s(x)` interprets x as signed, and `++` concatenates bits. `zextN` and `sextN` extend to N bits.
Instruction names link to their encodings, operands and architectural notes.

@anchor operands
The operands:

- `rd`, `rs`, `rs1`, `rs2`, `base`: register numbers, 0 to 7. `rd` is written; `rs`, `rs1` and
`rs2` are read; `base` holds an address.
- `imm`: an immediate byte, unsigned for `LIL` and `LIH`, signed (-128 to 127) for `ADDI`.
- `shamt`: a shift count, of which only bits 4 to 0 are used.
- `off`: a signed offset: in bytes (-16 to 15) for loads and stores, and in instructions for
branches (-128 to 127) and for `JMP` and `CALL` (-1024 to 1023).
 */
scattered union instruction

/*!
Maps each instruction to its word, and each word with an assigned opcode back to its instruction.
 */
val encdec : instruction <-> word
scattered mapping encdec

/*!
Carries out an instruction. It sees PC as the address of the instruction itself, and leaves the
address of the next one in `nextPC` for the drivers to commit. An instruction reads its operands
before it writes; `PUSH` and `POP` update R7 and memory in the order their clauses give.
 */
val execute : instruction -> unit
scattered function execute

$include "instructions/data_movement.sail"
$include "instructions/memory.sail"
$include "instructions/arithmetic.sail"
$include "instructions/logic.sail"
$include "instructions/shifts.sail"
$include "instructions/comparison.sail"
$include "instructions/control_flow.sail"
$include "instructions/stack.sail"

end instruction
end encdec
end execute

$include "step.sail"
$endif
