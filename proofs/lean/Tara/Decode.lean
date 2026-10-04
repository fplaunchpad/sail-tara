import Tara.Machine

/-!
# Decoding as a function

Sail generates `encdec_backwards_matches` and `encdec_backwards` in the monad, because
`encdec_backwards` fails on a word that no clause of `encdec` matches. Neither touches the state,
so `decode` runs `encdec_backwards` in the default state and keeps its instruction. The theorems
about `step` are stated with it. Each proof here abstracts the opcode and checks its 32 values.
-/

namespace Tara.Proofs

open Tara Tara.Functions

/-- The instruction a word decodes to, if a clause of `encdec` matches it. -/
def decode (w : BitVec 16) : Option instruction :=
  match (encdec_backwards w).run default with
  | .ok i _ => some i
  | .error _ _ => none

/-- Unfold the generated decoding of `w`, abstract its opcode, and check each of its 32 values. -/
local macro "by_opcode " w:ident : tactic =>
  `(tactic| (
    generalize hop : ($w).extractLsb 15 11 = op
    simp only [decode, encdec_backwards, encdec_backwards_matches, Sail.BitVec.extractLsb,
      ignored_backwards_matches, ignored_backwards, Sail.BitVec.length, hop]
    clear hop
    obtain ⟨n, hn, hn'⟩ : ∃ n, n < 32 ∧ op = BitVec.ofNat 5 n := ⟨op.toNat, op.isLt, by simp⟩
    subst hn'
    iterate 32 (rcases n with _ | n; · simp (config := {decide := true}) [EStateM.run, pure,
      EStateM.pure, throw, throwThe, MonadExceptOf.throw, EStateM.throw,
      Sail.ConcurrencyInterfaceV1.PreSail.assert, bind, EStateM.bind] <;>
      (try intro h; cases h; rfl))
    omega))

/-- A word fails to decode exactly when its opcode, the top five bits, is 27 or more. -/
theorem decode_eq_none_iff (w : BitVec 16) :
    decode w = none ↔ 27 ≤ (w.extractLsb 15 11).toNat := by
  by_opcode w

/-- `step`'s test of a word: whether the word decodes. -/
theorem encdec_backwards_matches_run (w : BitVec 16) (s : State) :
    (encdec_backwards_matches w).run s = .ok (decode w).isSome s := by
  have h := decode_eq_none_iff w
  have hm : (encdec_backwards_matches w).run s =
      .ok (decide ((w.extractLsb 15 11).toNat < 27)) s := by
    by_opcode w
  rw [hm]
  cases hd : decode w <;> simp_all <;> omega

/-- A word that decodes is decoded to that instruction, in any state. -/
theorem encdec_backwards_run (w : BitVec 16) (i : instruction) (h : decode w = some i)
    (s : State) : (encdec_backwards w).run s = .ok i s := by
  revert h
  by_opcode w

end Tara.Proofs
