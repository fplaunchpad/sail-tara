import Tara

/-!
# The instruction codec

`encode` writes an instruction as a 16-bit word: a 5-bit opcode, then operand fields. `decode`
reads the opcode and the fields back, ignoring the unused padding bits, and returns `none` for the
unassigned opcodes. The round trip is proved without computing over the 30355 instructions: the
fields of an encoded word are read back by general lemmas about `extractLsb` of an append.
-/

namespace Tara.Proofs

open Tara Tara.Functions

deriving instance DecidableEq for instruction

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

/-! ## Reading fields back from an encoded word -/

/-- The opcode of `op ++ rest`. -/
theorem extract_op (op : BitVec 5) (rest : BitVec 11) : (op +++ rest).extractLsb 15 11 = op :=
  BitVec.extractLsb'_append_eq_left

/-- Encoded instructions carry the opcode assigned to their constructor. -/
theorem encode_opcode (i : instruction) : (encode i).extractLsb 15 11 = opcode i := by
  cases i <;> exact BitVec.extractLsb'_append_eq_left

/-- Bits 10 to 8 of `op ++ (a ++ b)`: the first register field. -/
theorem extract_rd (op : BitVec 5) (a : BitVec 3) (b : BitVec 8) :
    (op +++ (a +++ b)).extractLsb 10 8 = a := by
  show (op ++ (a ++ b)).extractLsb' 8 3 = a
  rw [BitVec.extractLsb'_append_eq_of_add_le (by omega)]
  exact BitVec.extractLsb'_append_eq_left

/-- Bits 7 to 0 of `op ++ (a ++ b)`: the 8-bit immediate. -/
theorem extract_imm (op : BitVec 5) (a : BitVec 3) (b : BitVec 8) :
    (op +++ (a +++ b)).extractLsb 7 0 = b := by
  show (op ++ (a ++ b)).extractLsb' 0 8 = b
  rw [BitVec.extractLsb'_append_eq_of_add_le (by omega)]
  exact BitVec.extractLsb'_append_eq_right

/-- Bits 7 to 5 of `op ++ (a ++ (d ++ e))`: the second register field. -/
theorem extract_rs (op : BitVec 5) (a : BitVec 3) (d : BitVec 3) (e : BitVec 5) :
    (op +++ (a +++ (d +++ e))).extractLsb 7 5 = d := by
  show (op ++ (a ++ (d ++ e))).extractLsb' 5 3 = d
  rw [BitVec.extractLsb'_append_eq_of_add_le (by omega),
    BitVec.extractLsb'_append_eq_of_add_le (by omega)]
  exact BitVec.extractLsb'_append_eq_left

/-- Bits 4 to 0 of `op ++ (a ++ (d ++ e))`: the 5-bit offset. -/
theorem extract_off5 (op : BitVec 5) (a : BitVec 3) (d : BitVec 3) (e : BitVec 5) :
    (op +++ (a +++ (d +++ e))).extractLsb 4 0 = e := by
  show (op ++ (a ++ (d ++ e))).extractLsb' 0 5 = e
  rw [BitVec.extractLsb'_append_eq_of_add_le (by omega),
    BitVec.extractLsb'_append_eq_of_add_le (by omega)]
  exact BitVec.extractLsb'_append_eq_right

/-- Bits 4 to 2 of `op ++ (a ++ (d ++ (e ++ g)))`: the third register field. -/
theorem extract_rs2 (op : BitVec 5) (a : BitVec 3) (d : BitVec 3) (e : BitVec 3) (g : BitVec 2) :
    (op +++ (a +++ (d +++ (e +++ g)))).extractLsb 4 2 = e := by
  show (op ++ (a ++ (d ++ (e ++ g)))).extractLsb' 2 3 = e
  rw [BitVec.extractLsb'_append_eq_of_add_le (by omega),
    BitVec.extractLsb'_append_eq_of_add_le (by omega),
    BitVec.extractLsb'_append_eq_of_add_le (by omega)]
  exact BitVec.extractLsb'_append_eq_left

/-- Bits 10 to 0 of `op ++ rest`: the 11-bit offset. -/
theorem extract_off11 (op : BitVec 5) (rest : BitVec 11) : (op +++ rest).extractLsb 10 0 = rest :=
  BitVec.extractLsb'_append_eq_right

/-! ## The round trip -/

/-- Read the operand fields of an encoded word back, wherever `decode` extracts them. -/
local macro "read_fields" : tactic =>
  `(tactic| repeat (first
      | rw [extract_rd] | rw [extract_imm] | rw [extract_rs]
      | rw [extract_off5] | rw [extract_rs2] | rw [extract_off11]))

/-- Unfold `decode` on an encoded word, find its opcode, and read the fields back. -/
local macro "roundtrip" : tactic =>
  `(tactic| (simp only [decode, Sail.BitVec.extractLsb]
             rw [encode_opcode]
             simp only [opcode, encode]
             simp (config := {decide := true}) only [ite_true, ite_false, ↓reduceIte]
             read_fields))

/-- Decoding an encoded instruction gives the instruction back. -/
theorem decode_encode (i : instruction) : decode (encode i) = some i := by
  cases i with
  | NOP u => cases u; roundtrip
  | HLT u => cases u; roundtrip
  | MOV a => obtain ⟨rd, rs⟩ := a; roundtrip
  | LIL a => obtain ⟨rd, imm⟩ := a; roundtrip
  | LIH a => obtain ⟨rd, imm⟩ := a; roundtrip
  | LDW a => obtain ⟨rd, base, off⟩ := a; roundtrip
  | STW a => obtain ⟨rs, base, off⟩ := a; roundtrip
  | LDB a => obtain ⟨rd, base, off⟩ := a; roundtrip
  | STB a => obtain ⟨rs, base, off⟩ := a; roundtrip
  | ADD a => obtain ⟨rd, rs1, rs2⟩ := a; roundtrip
  | SUB a => obtain ⟨rd, rs1, rs2⟩ := a; roundtrip
  | ADDI a => obtain ⟨rd, imm⟩ := a; roundtrip
  | MUL a => obtain ⟨rd, rs1, rs2⟩ := a; roundtrip
  | AND a => obtain ⟨rd, rs1, rs2⟩ := a; roundtrip
  | OR a => obtain ⟨rd, rs1, rs2⟩ := a; roundtrip
  | XOR a => obtain ⟨rd, rs1, rs2⟩ := a; roundtrip
  | NOT a => obtain ⟨rd, rs⟩ := a; roundtrip
  | SHL a => obtain ⟨rd, shamt⟩ := a; roundtrip
  | SHR a => obtain ⟨rd, shamt⟩ := a; roundtrip
  | SLT a => obtain ⟨rd, rs1, rs2⟩ := a; roundtrip
  | BZ a => obtain ⟨rs, off⟩ := a; roundtrip
  | BN a => obtain ⟨rs, off⟩ := a; roundtrip
  | JMP a => roundtrip
  | CALL a => roundtrip
  | RET u => cases u; roundtrip
  | PUSH a => roundtrip
  | POP a => roundtrip

/-- Distinct instructions have distinct encodings. -/
theorem encode_injective : Function.Injective encode := by
  intro i j h
  have := decode_encode i
  rw [h, decode_encode j] at this
  exact (Option.some.inj this).symm

/-- A conditional that yields `some x` or `o` is `none` when the condition fails and `o` is. -/
theorem ite_some_eq_none {α : Type} (c : Prop) [Decidable c] (a : α) (o : Option α) :
    (if c then some a else o) = none ↔ ¬c ∧ o = none := by
  split <;> simp_all

/-- A word fails to decode exactly when its opcode, the top five bits, is 27 or more. -/
theorem decode_eq_none_iff (w : BitVec 16) :
    decode w = none ↔ 27 ≤ (w.extractLsb 15 11).toNat := by
  generalize hop : w.extractLsb 15 11 = op
  simp only [decode, Sail.BitVec.extractLsb, hop, ite_some_eq_none]
  simp only [beq_iff_eq]
  clear hop
  revert op
  decide

end Tara.Proofs
