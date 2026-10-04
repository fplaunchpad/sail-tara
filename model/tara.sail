/* TARA instruction semantics.
 *
 * Each instruction gives its operands, its 16-bit encoding (5-bit opcode, then operand fields) and
 * its effect, side by side, in the file of its group under instructions/. Decoding ignores the
 * unused padding bits; encoding writes them as zero. rd is a destination; rs, rs1 and rs2 are
 * sources. X(r) reads or writes a register. Arithmetic wraps at 16 bits. Memory offsets count
 * bytes; branch offsets count instructions.
 *
 * execute sees PC as the address of the current instruction and proposes the successor in nextPC;
 * the drivers in step.sail commit it.
 */

$ifndef _TARA_SAIL
$define _TARA_SAIL
$include "machine.sail"

/*! An instruction is one 16-bit word, stored big-endian like every word. Bits 15 to 11 hold the
opcode; the other 11 bits are divided into fields by one of eight formats, F0 to F7 (the names are
those of the Studio manual). A field written as zeros is padding: `decode` ignores it and `encode`
writes it as zeros, so every word with an assigned opcode decodes, and several words give the same
instruction.
 */
$anchor encoding

/*! The operands of the instructions are named as follows.

- `rd`, `rs`, `rs1`, `rs2`, `base`: a register number, 0 to 7. `rd` is the destination; `rs`, `rs1`
and `rs2` are sources; `base` holds a memory address.
- `imm`: an immediate byte, unsigned for `LIL` and `LIH`, two's complement (-128 to 127) for `ADDI`.
- `shamt`: a shift count; only bits 4 to 0 are used.
- `off`: a signed offset, in bytes (-16 to 15) for the memory instructions and in instructions for
the branches (-128 to 127) and for `JMP` and `CALL` (-1024 to 1023).
 */
$anchor operands

scattered union instruction

/*! Turns an instruction into its 16-bit word: the opcode, then the fields, with the padding written
as zeros.
 */
val encode : instruction -> word
scattered function encode

/*! Turns a word into an instruction, or `None`. Each clause matches the opcode in bits 15 to 11 and
ignores the padding.
 */
val decode : word -> option(instruction)
scattered function decode

/*! Carries out an instruction. It reads and writes the machine state; it sees PC as the address of
the instruction itself and proposes the successor in `nextPC`, which the drivers commit. An
instruction reads its sources before it writes its result. `PUSH` and `POP` take two steps that
depend on each other, and they take them in the order of their clauses.
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

/*! Opcodes 27 to 31 are unassigned: no instruction decodes from them, and `step` reports them as
`Illegal`.
 */
function clause decode(_) = None()

end instruction
end encode
end decode
end execute

$include "step.sail"
$endif
