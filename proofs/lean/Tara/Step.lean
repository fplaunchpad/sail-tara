import Tara.Execute
import Tara.Decode

/-!
# What `step` does to a machine

`step` fetches the word at PC and decodes it with `encdec`. A halted CPU stops, an illegal word
advances PC and reports itself, and anything else retires, and `retire` leaves PC masked to 11
bits. `step_spec` packages the three cases for the theorems in `Tara/Properties.lean`.
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
`execute` leaves that successor at PC + 2 unless the instruction chooses it. -/
theorem retire_spec (insn : instruction) (m : Machine) :
    ∃ m' : Machine, (∀ s, (retire insn).run (m.within s) = .ok (.Retired ()) (m'.within s)) ∧
      m'.pc < 0x800#16 ∧ m'.keys = m.keys ∧
      (¬ Stores insn → m'.mem = m.mem) ∧
      (insn ≠ .HLT () → m'.halted = m.halted) ∧ (insn = .HLT () → m'.halted = true) ∧
      (¬ Branches insn → m'.pc = pc_mask (m.pc + 2#16)) := by
  obtain ⟨m₂, hrun, -, hkeys, hmem, hhalt, hhalt', hnext⟩ :=
    execute_spec insn { m with nextPC := m.pc + 2#16 }
  refine ⟨{ m₂ with pc := pc_mask m₂.nextPC }, fun s => ?_, ?_⟩
  · simp [retire, hrun]
  · refine ⟨pc_mask_lt _, hkeys, hmem, hhalt, hhalt', fun hb => ?_⟩
    simp [hnext hb]

/-! ## Stepping -/

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

/-- What `step keys` does to a machine, whatever surrounds the registers: it succeeds, and either

* the CPU is halted and nothing changes, or
* the fetched word does not decode: the result is `Illegal` and only KEYS and PC change, or
* the fetched word decodes to an instruction that retires. -/
theorem step_spec (m : Machine) (keys : BitVec 5) :
    ∃ (r : retirement) (m' : Machine),
      (∀ s, (step keys).run (m.within s) = .ok r (m'.within s)) ∧
      (m.halted = true ∧ r = .Stopped () ∧ m' = m ∨
       m.halted = false ∧ decode (m.fetch keys) = none ∧ r = .Illegal (m.fetch keys) ∧
         m' = { m with keys := keys, pc := pc_mask (m.pc + 2#16) } ∨
       m.halted = false ∧ ∃ insn, decode (m.fetch keys) = some insn ∧ r = .Retired () ∧
         m'.pc < 0x800#16 ∧ m'.keys = keys ∧ (¬ Stores insn → m'.mem = m.mem) ∧
         (insn ≠ .HLT () → m'.halted = false) ∧ (insn = .HLT () → m'.halted = true) ∧
         (¬ Branches insn → m'.pc = pc_mask (m.pc + 2#16))) := by
  by_cases h : m.halted = true
  · exact ⟨_, m, fun s => step_of_halted m s keys h, Or.inl ⟨h, rfl, rfl⟩⟩
  · have h' : m.halted = false := by simpa using h
    by_cases hd : decode (m.fetch keys) = none
    · exact ⟨_, _, fun s => step_of_illegal m s keys h' hd, Or.inr (Or.inl ⟨h', hd, rfl, rfl⟩)⟩
    · obtain ⟨insn, hd⟩ := Option.ne_none_iff_exists'.mp hd
      obtain ⟨m', hrun, hpc, hkeys, hmem, hhalt, hhalt', hnext⟩ :=
        retire_spec insn { m with keys := keys }
      refine ⟨_, m', fun s => ?_,
        Or.inr (Or.inr ⟨h', insn, hd, rfl, hpc, hkeys, hmem, ?_, hhalt', hnext⟩)⟩
      · rw [step_of_decoded m s keys h' insn hd]
        exact hrun s
      · intro hne
        simpa [h'] using hhalt hne

/-- `step_spec` for a step known to run from `m` to `m'`: the result is one of its three cases. -/
theorem step_cases {m m' : Machine} {keys : BitVec 5} {s : State} {r : retirement}
    (h : (step keys).run (m.within s) = .ok r (m'.within s)) :
    m.halted = true ∧ r = .Stopped () ∧ m' = m ∨
    m.halted = false ∧ decode (m.fetch keys) = none ∧ r = .Illegal (m.fetch keys) ∧
      m' = { m with keys := keys, pc := pc_mask (m.pc + 2#16) } ∨
    m.halted = false ∧ ∃ insn, decode (m.fetch keys) = some insn ∧ r = .Retired () ∧
      m'.pc < 0x800#16 ∧ m'.keys = keys ∧ (¬ Stores insn → m'.mem = m.mem) ∧
      (insn ≠ .HLT () → m'.halted = false) ∧ (insn = .HLT () → m'.halted = true) ∧
      (¬ Branches insn → m'.pc = pc_mask (m.pc + 2#16)) := by
  obtain ⟨r₀, m₀, hall, hcase⟩ := step_spec m keys
  rw [hall s] at h
  obtain ⟨rfl, hm⟩ := EStateM.Result.ok.inj h
  obtain rfl := Machine.within_inj hm
  exact hcase

end Tara.Proofs
