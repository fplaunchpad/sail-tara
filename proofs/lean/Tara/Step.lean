import Tara.Execute
import Tara.Decode

/-!
# What `step` does to a machine

`step` fetches the word at PC and decodes it with `encdec`. A halted CPU stops, a word that does
not decode is reported and skipped, and any other word retires its instruction, which leaves PC
masked to 11 bits. `StepCase` names the three outcomes, and `step_spec` shows that every step has
one of them.
-/

namespace Tara.Proofs

open Tara Tara.Functions Tara.Register Sail.ConcurrencyInterfaceV1

/-- The machine invariant: PC < 0x800. -/
def Machine.WF (m : Machine) : Prop := m.pc < 0x800#16

/-- PC < 0x800 says PC's upper five bits are zero. -/
theorem Machine.wf_iff (m : Machine) : m.WF ↔ m.pc.extractLsb 15 11 = 0#5 := by
  unfold Machine.WF
  rw [BitVec.lt_def, ← BitVec.toNat_inj, BitVec.extractLsb_toNat]
  have := m.pc.isLt
  simp
  omega

/-! ## PC arithmetic -/

/-- `pc_mask` keeps the low 11 bits of a PC. -/
theorem pc_mask_toNat (v : BitVec 16) : (pc_mask v).toNat = v.toNat % 2048 := by
  unfold pc_mask Sail.BitVec.extractLsb
  rw [BitVec.toNat_append, BitVec.extractLsb_toNat]
  simp

/-- A masked PC is below 0x800. -/
theorem pc_mask_lt (v : BitVec 16) : pc_mask v < 0x800#16 := by
  rw [BitVec.lt_def, pc_mask_toNat]
  simp
  omega

/-- The masked successor PC is the sum modulo 2048: 2048 divides the 16-bit wrap-around. -/
theorem pc_mask_add_two (pc : BitVec 16) :
    (pc_mask (pc + 2#16)).toNat = (pc.toNat + 2) % 2048 := by
  rw [pc_mask_toNat, BitVec.toNat_add]
  simp

/-! ## Fetching -/

/-- The word `step keys` fetches from `m`: the word at PC, with the input lines set to `keys`. -/
def Machine.fetch (m : Machine) (keys : BitVec 5) : BitVec 16 :=
  ({ m with keys := keys } : Machine).readWord m.pc

/-! ## Retiring -/

/-- Retiring an instruction succeeds and sets PC from the proposed successor, masked to 11 bits.
`retire` proposes PC + 2 before executing, and only a branch proposes another. -/
theorem retire_spec (insn : instruction) (m : Machine) :
    ∃ m' : Machine, (∀ s, (retire insn).run (m.within s) = .ok (.Retired ()) (m'.within s)) ∧
      m'.pc < 0x800#16 ∧ m'.keys = m.keys ∧
      (¬ Stores insn → m'.mem = m.mem) ∧
      (insn ≠ .HLT () → m'.halted = m.halted) ∧ (insn = .HLT () → m'.halted = true) ∧
      (¬ Branches insn → m'.pc = pc_mask (m.pc + 2#16)) := by
  obtain ⟨m₂, hrun, hframe⟩ := execute_spec insn { m with nextPC := m.pc + 2#16 }
  refine ⟨{ m₂ with pc := pc_mask m₂.nextPC }, fun s => by simp [retire, hrun], pc_mask_lt _,
    hframe.keys, hframe.mem, hframe.halted, hframe.hlt, fun hb => ?_⟩
  simp [hframe.nextPC hb]

/-! ## Stepping -/

/-- The three things `step keys` can do to a machine `m`: its result and the machine it leaves. -/
inductive StepCase (m : Machine) (keys : BitVec 5) : retirement → Machine → Prop
  /-- A halted CPU stops, and nothing changes. -/
  | stopped (halted : m.halted = true) : StepCase m keys (.Stopped ()) m
  /-- A fetched word that does not decode is reported, and only KEYS and PC change. -/
  | illegal (running : m.halted = false) (illegal : decode (m.fetch keys) = none) :
      StepCase m keys (.Illegal (m.fetch keys)) { m with keys := keys, pc := pc_mask (m.pc + 2#16) }
  /-- A fetched word that decodes retires its instruction. -/
  | retired {m' : Machine} (insn : instruction) (running : m.halted = false)
      (decoded : decode (m.fetch keys) = some insn) (pc_lt : m'.pc < 0x800#16)
      (keys_eq : m'.keys = keys) (mem : ¬ Stores insn → m'.mem = m.mem)
      (halted : insn ≠ .HLT () → m'.halted = false) (hlt : insn = .HLT () → m'.halted = true)
      (sequential : ¬ Branches insn → m'.pc = pc_mask (m.pc + 2#16)) :
      StepCase m keys (.Retired ()) m'

private theorem step_of_halted (m : Machine) (s : State) (keys : BitVec 5) (h : m.halted = true) :
    (step keys).run (m.within s) = .ok (.Stopped ()) (m.within s) := by
  simp [step, h]

private theorem step_of_illegal (m : Machine) (s : State) (keys : BitVec 5)
    (h : m.halted = false) (hd : decode (m.fetch keys) = none) :
    (step keys).run (m.within s) = .ok (.Illegal (m.fetch keys))
      ({ m with keys := keys, pc := pc_mask (m.pc + 2#16) }.within s) := by
  simp [step, h, Machine.fetch] at hd ⊢
  simp [encdec_backwards_matches_run, hd]

private theorem step_of_decoded (m : Machine) (s : State) (keys : BitVec 5)
    (h : m.halted = false) (insn : instruction) (hd : decode (m.fetch keys) = some insn) :
    (step keys).run (m.within s) = (retire insn).run ({ m with keys := keys }.within s) := by
  simp [step, h, Machine.fetch] at hd ⊢
  simp [encdec_backwards_matches_run, encdec_backwards_run _ insn hd, hd]

/-- What `step keys` does to a machine, whatever surrounds the registers: it succeeds, with one of
the outcomes of `StepCase`. -/
theorem step_spec (m : Machine) (keys : BitVec 5) :
    ∃ (r : retirement) (m' : Machine),
      (∀ s, (step keys).run (m.within s) = .ok r (m'.within s)) ∧ StepCase m keys r m' := by
  cases hh : m.halted
  · cases hd : decode (m.fetch keys) with
    | none => exact ⟨_, _, fun s => step_of_illegal m s keys hh hd, .illegal hh hd⟩
    | some insn =>
      obtain ⟨m', hrun, hpc, hkeys, hmem, hhalt, hhlt, hseq⟩ :=
        retire_spec insn { m with keys := keys }
      exact ⟨_, m', fun s => (step_of_decoded m s keys hh insn hd).trans (hrun s),
        .retired insn hh hd hpc hkeys hmem (fun hne => (hhalt hne).trans hh) hhlt hseq⟩
  · exact ⟨_, m, fun s => step_of_halted m s keys hh, .stopped hh⟩

/-- `step_spec` for a step known to run from `m` to `m'`. -/
theorem step_cases {m m' : Machine} {keys : BitVec 5} {s : State} {r : retirement}
    (h : (step keys).run (m.within s) = .ok r (m'.within s)) : StepCase m keys r m' := by
  obtain ⟨r₀, m₀, hall, hcase⟩ := step_spec m keys
  obtain ⟨rfl, rfl⟩ := Machine.ok_within_inj ((hall s).symm.trans h)
  exact hcase

end Tara.Proofs
