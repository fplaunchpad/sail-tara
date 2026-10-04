import Tara.Decode

/-!
# The instruction codec

`encdec_forwards` writes an instruction as a 16-bit word: a 5-bit opcode, then operand fields.
`decode` reads the opcode and the fields back through `encdec_backwards`, ignoring the unused bits.
The round trip is proved without computing over the 30355 instructions: core lemmas about
`extractLsb'` of an append read each field of an encoded word back.
-/

namespace Tara.Proofs

open Tara Tara.Functions

/-- The opcode assigned to each instruction constructor. -/
def opcode : instruction → BitVec 5
  | .NOP _ => 0b00000#5
  | .HLT _ => 0b00001#5
  | .MOV _ => 0b00010#5
  | .LIL _ => 0b00011#5
  | .LIH _ => 0b00100#5
  | .LDW _ => 0b00101#5
  | .STW _ => 0b00110#5
  | .LDB _ => 0b00111#5
  | .STB _ => 0b01000#5
  | .ADD _ => 0b01001#5
  | .SUB _ => 0b01010#5
  | .ADDI _ => 0b01011#5
  | .MUL _ => 0b01100#5
  | .AND _ => 0b01101#5
  | .OR _ => 0b01110#5
  | .XOR _ => 0b01111#5
  | .NOT _ => 0b10000#5
  | .SHL _ => 0b10001#5
  | .SHR _ => 0b10010#5
  | .SLT _ => 0b10011#5
  | .BZ _ => 0b10100#5
  | .BN _ => 0b10101#5
  | .JMP _ => 0b10110#5
  | .CALL _ => 0b10111#5
  | .RET _ => 0b11000#5
  | .PUSH _ => 0b11001#5
  | .POP _ => 0b11010#5

/-- Encoded instructions carry the opcode assigned to their constructor. -/
theorem encode_opcode (i : instruction) : (encdec_forwards i).extractLsb 15 11 = opcode i := by
  cases i <;> exact BitVec.extractLsb'_append_eq_left

/-- Decoding an encoded instruction gives the instruction back. -/
theorem decode_encode (i : instruction) : decode (encdec_forwards i) = some i := by
  cases i <;> simp (config := {decide := true}) (disch := omega) only [decode, encdec_backwards,
    encdec_forwards, ignored_forwards, ignored_backwards, ignored_backwards_matches,
    Sail.BitVec.extractLsb, Sail.BitVec.length, BitVec.extractLsb,
    BitVec.extractLsb'_append_eq_of_add_le, BitVec.extractLsb'_append_eq_left,
    BitVec.extractLsb'_eq_self, Bool.true_and, ↓reduceIte] <;> rfl

/-- Distinct instructions have distinct encodings. -/
theorem encode_injective : Function.Injective encdec_forwards := by
  intro i j h
  have := decode_encode i
  rw [h, decode_encode j] at this
  exact (Option.some.inj this).symm

end Tara.Proofs
