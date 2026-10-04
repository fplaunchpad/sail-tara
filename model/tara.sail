/* TARA's instructions. Each instruction's operands, encoding and effect sit together in the file
 * of its group under instructions/; the drivers in step.sail run them.
 */

$ifndef _TARA_SAIL
$define _TARA_SAIL
$include "machine.sail"

/*!
== The instruction set */
$anchor section_instruction_set

/*!
An instruction is one word: a 5-bit opcode in bits 15 to 11, then its operand fields. Bits that no
field uses are padding, which `decode` ignores and `encode` writes as zeros, so several words can
decode to the same instruction. The formats group the instructions by the names and widths of their
fields.
 */
$anchor encoding

/*!
=== Instruction formats */
$anchor section_instruction_formats

/*!
=== Opcodes */
$anchor section_opcodes

/*!
The operands:

- `rd`, `rs`, `rs1`, `rs2`, `base`: register numbers, 0 to 7. `rd` is written; `rs`, `rs1` and
`rs2` are read; `base` holds an address.
- `imm`: an immediate byte, unsigned for `LIL` and `LIH`, signed (-128 to 127) for `ADDI`.
- `shamt`: a shift count, of which only bits 4 to 0 are used.
- `off`: a signed offset: in bytes (-16 to 15) for loads and stores, and in instructions for
branches (-128 to 127) and for `JMP` and `CALL` (-1024 to 1023).
 */
$anchor operands

scattered union instruction

/*!
The word of an instruction: its opcode and fields, with zeros for padding. */
val encode : instruction -> word
scattered function encode

/*!
The instruction in a word, or `None`. Each clause matches an opcode and ignores the padding. */
val decode : word -> option(instruction)
scattered function decode

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

/*!
Opcodes 27 to 31 are unassigned: they decode to `None`, and `step` reports them as `Illegal`. */
function clause decode(_) = None()

end instruction
end encode
end decode
end execute

$include "step.sail"
$endif
