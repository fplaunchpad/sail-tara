import Lean
import Tara.Codec
import Tara.Step

/-!
# Properties of the generated model

Every theorem is about the Lean that Sail generates from `model/`: `step`, `retire`, `execute`,
`encdec_forwards`, `encdec_backwards`, `reset` and `sail_model_init`, run in the generated monad
`SailM`. `decode` (`Tara/Decode.lean`) reads what `encdec_backwards` returns.

A machine state is a value for every register (`Machine`, in `Tara/Machine.lean`). Sail keeps the
registers in a state `s : State` next to bookkeeping that the model never touches, and `m.within s`
is `s` with the registers of `m`. `(act).run st` is the monad's run function: `.ok r st'` when `act`
succeeds with result `r` in the state `st'`, and `.error e st'` when it fails.

| Property                    | Theorems                                                          |
| --------------------------- | ----------------------------------------------------------------- |
| 1. Progress                 | `step_progress`, `step_progress_of_complete`,                     |
|                             | `step_fails_without_registers`                                    |
| 2. Preservation of `wf`     | `step_preserves_wf`, `reset_wf`, `sail_model_init_wf`,            |
|                             | `steps_safe`, `power_on_safe`                                     |
| 3. Halting is absorbing     | `step_halted`                                                     |
| 4. Codec                    | `encode_opcode`, `decode_encode`, `encode_injective`,             |
|                             | `decode_eq_none_iff` (`Tara/Codec.lean`, `Tara/Decode.lean`)      |
| 5. Illegal step             | `step_illegal`, `step_illegal_pc`, `step_illegal_of_opcode`       |
| 6. Frame conditions         | `execute_memory`, `execute_halted`, `execute_hlt`,                |
|                             | `retire_sequential`, `step_memory`, `step_halts`,                 |
|                             | `step_sequential`                                                 |

The invariant `Machine.WF` is `PC < 0x800`, that is, PC's upper five bits are zero
(`Machine.wf_iff`).
-/

namespace Tara.Proofs

open Tara Tara.Functions Tara.Register Sail.ConcurrencyInterfaceV1

/-! ## 1. Progress -/

/-- Progress and determinism: from every machine state, with any input lines, `step` succeeds, and
its result and next machine are the same whatever Sail state surrounds the registers. Nothing
outside the registers changes: the model never asks for an undefined value. -/
theorem step_progress (m : Machine) (keys : BitVec 5) :
    ∃ (r : retirement) (m' : Machine),
      ∀ s : State, (step keys).run (m.within s) = .ok r (m'.within s) := by
  obtain ⟨r, m', h, -⟩ := step_spec m keys
  exact ⟨r, m', h⟩

/-- Progress for Sail states: `step` succeeds from every state that has all the registers. -/
theorem step_progress_of_complete {s : State} (hs : s.Complete) (keys : BitVec 5) :
    ∃ (r : retirement) (s' : State), (step keys).run s = .ok r s' := by
  obtain ⟨m, hm⟩ := State.exists_machine hs
  obtain ⟨r, m', h⟩ := step_progress m keys
  exact ⟨r, m'.within s, (congrArg (step keys).run hm).trans (h s)⟩

/-- Progress needs the registers: from a state that has none, `step` fails reading HALTED. -/
theorem step_fails_without_registers (keys : BitVec 5) :
    (step keys).run (default : State) = .error .Unreachable default := by
  have : (default : State).regs = ∅ := rfl
  simp [step, readReg, PreSail.readReg, this]
  rfl

/-! ## 2. Preservation of the invariant -/

/-- Preservation: if PC is below 0x800 and a step runs from `m` to `m'`, PC is below 0x800 in `m'`.
Only a halted CPU needs the hypothesis: every other step ends by writing PC masked to 11 bits. -/
theorem step_preserves_wf {m m' : Machine} {keys : BitVec 5} {s : State} {r : retirement}
    (hwf : m.WF) (h : (step keys).run (m.within s) = .ok r (m'.within s)) : m'.WF := by
  cases step_cases h with
  | stopped => exact hwf
  | illegal => exact pc_mask_lt _
  | retired _ _ _ hpc => exact hpc

/-- The reset button restarts from PC 0 with the CPU running, so the invariant holds. -/
theorem reset_wf (m : Machine) (s : State) :
    (reset ()).run (m.within s) = .ok () ({ m with pc := 0#16, halted := false }.within s) ∧
      ({ m with pc := 0#16, halted := false } : Machine).WF := by
  exact ⟨by simp [reset], by simp [Machine.WF]⟩

/-- The machine with every register zero and the CPU running. -/
def Machine.zero : Machine where
  gpr := Vector.replicate 8 0#16
  pc := 0#16
  mem := Vector.replicate 2048 0#8
  halted := false
  keys := 0#5
  nextPC := 0#16

/-- Power-on: `sail_model_init` gives every register an undefined value, which the model's choice
source resolves to zero. So from any Sail state the machine is all zeros and the invariant
holds. -/
theorem sail_model_init_wf (s : State) :
    (sail_model_init ()).run s = .ok () (Machine.zero.within s) ∧ Machine.zero.WF := by
  refine ⟨?_, by simp [Machine.WF, Machine.zero]⟩
  have h : (sail_model_init ()).run s =
      .ok () { s with regs := Machine.zero.overwrite s.regs } := rfl
  rw [h, Machine.regs_overwrite]
  rfl

/-- Step once for each of a list of input-line values. -/
def steps : List (BitVec 5) → SailM Unit
  | [] => pure ()
  | keys :: rest => do
    let _ ← step keys
    steps rest

/-- Progress and preservation together: from a machine with PC below 0x800, any number of steps,
whatever input lines they are given, succeed and end in a machine with PC below 0x800. -/
theorem steps_safe (inputs : List (BitVec 5)) :
    ∀ (m : Machine) (s : State), m.WF →
      ∃ m' : Machine, (steps inputs).run (m.within s) = .ok () (m'.within s) ∧ m'.WF := by
  induction inputs with
  | nil => exact fun m s hwf => ⟨m, by simp [steps], hwf⟩
  | cons keys rest ih =>
    intro m s hwf
    obtain ⟨r, m₁, hall⟩ := step_progress m keys
    have h₁ := hall s
    obtain ⟨m', hrun, hwf'⟩ := ih m₁ s (step_preserves_wf hwf h₁)
    exact ⟨m', by simp [steps, h₁, hrun], hwf'⟩

/-- Safety from power-on: after `sail_model_init`, any number of steps with any input lines succeed
and keep PC below 0x800. -/
theorem power_on_safe (inputs : List (BitVec 5)) (s : State) :
    ∃ m' : Machine,
      (sail_model_init () >>= fun _ => steps inputs).run s = .ok () (m'.within s) ∧ m'.WF := by
  obtain ⟨hinit, hwf⟩ := sail_model_init_wf s
  obtain ⟨m', hrun, hwf'⟩ := steps_safe inputs Machine.zero s hwf
  exact ⟨m', by simp [hinit, hrun], hwf'⟩

/-! ## 3. Halting is absorbing -/

/-- When HALTED is true, `step` returns `Stopped` and leaves the state, KEYS included, unchanged.
This holds in every Sail state, whether or not it has all the registers. -/
theorem step_halted {s : State} (h : s.regs.get? HALTED = some true) (keys : BitVec 5) :
    (step keys).run s = .ok (.Stopped ()) s := by
  simp [step, readReg, PreSail.readReg, h]

/-! ## 5. Illegal steps

(4 is in `Tara/Codec.lean` and `Tara/Decode.lean`.) -/

/-- When the CPU runs and the fetched word does not decode, `step` returns `Illegal` with that word
and changes only KEYS, to `keys`, and PC, to the masked PC + 2. -/
theorem step_illegal {m : Machine} (keys : BitVec 5) (s : State) (hrun : m.halted = false)
    (hd : decode (m.fetch keys) = none) :
    (step keys).run (m.within s) = .ok (.Illegal (m.fetch keys))
      ({ m with keys := keys, pc := pc_mask (m.pc + 2#16) }.within s) := by
  obtain ⟨r, m', hall, hcase⟩ := step_spec m keys
  cases hcase with
  | stopped hh => simp [hh] at hrun
  | illegal => exact hall s
  | retired _ _ hd' => simp [hd] at hd'

/-- After an illegal step PC is (PC + 2) mod 2048. -/
theorem step_illegal_pc {m m' : Machine} {keys : BitVec 5} {s : State} {w : BitVec 16}
    (h : (step keys).run (m.within s) = .ok (.Illegal w) (m'.within s)) :
    m'.pc.toNat = (m.pc.toNat + 2) % 2048 := by
  cases step_cases h with
  | illegal => exact pc_mask_add_two m.pc

/-- A word whose opcode, the top five bits, is 27 or more is illegal. -/
theorem step_illegal_of_opcode {m : Machine} (keys : BitVec 5) (s : State)
    (hrun : m.halted = false) (hop : 27 ≤ ((m.fetch keys).extractLsb 15 11).toNat) :
    (step keys).run (m.within s) = .ok (.Illegal (m.fetch keys))
      ({ m with keys := keys, pc := pc_mask (m.pc + 2#16) }.within s) :=
  step_illegal keys s hrun ((decode_eq_none_iff _).mpr hop)

/-! ## 6. Frame conditions

What an instruction, and so a step, leaves alone. -/

/-- Only STW, STB and PUSH change memory: executing any other instruction leaves it as it was. -/
theorem execute_memory {insn : instruction} {m m' : Machine} {s : State}
    (h : (execute insn).run (m.within s) = .ok () (m'.within s)) (hn : ¬ Stores insn) :
    m'.mem = m.mem :=
  (execute_frame h).mem hn

/-- Only HLT sets HALTED: executing any other instruction leaves it as it was. -/
theorem execute_halted {insn : instruction} {m m' : Machine} {s : State}
    (h : (execute insn).run (m.within s) = .ok () (m'.within s)) (hn : insn ≠ .HLT ()) :
    m'.halted = m.halted :=
  (execute_frame h).halted hn

/-- HLT sets HALTED. -/
theorem execute_hlt {m m' : Machine} {s : State}
    (h : (execute (.HLT ())).run (m.within s) = .ok () (m'.within s)) : m'.halted = true :=
  (execute_frame h).hlt rfl

/-- Every instruction other than BZ, BN, JMP, CALL and RET retires with PC set to
(PC + 2) mod 2048. -/
theorem retire_sequential {insn : instruction} (hn : ¬ Branches insn) (m : Machine) (s : State) :
    ∃ m' : Machine, (retire insn).run (m.within s) = .ok (.Retired ()) (m'.within s) ∧
      m'.pc.toNat = (m.pc.toNat + 2) % 2048 := by
  obtain ⟨m', hrun, -, -, -, -, -, hpc⟩ := retire_spec insn m
  exact ⟨m', hrun s, by rw [hpc hn, pc_mask_add_two]⟩

/-- A step changes memory only by retiring a store. -/
theorem step_memory {m m' : Machine} {keys : BitVec 5} {s : State} {r : retirement}
    (h : (step keys).run (m.within s) = .ok r (m'.within s)) :
    m'.mem = m.mem ∨ ∃ insn, decode (m.fetch keys) = some insn ∧ Stores insn := by
  cases step_cases h with
  | stopped => exact Or.inl rfl
  | illegal => exact Or.inl rfl
  | retired insn _ hd _ _ hmem =>
    by_cases hs : Stores insn
    · exact Or.inr ⟨insn, hd, hs⟩
    · exact Or.inl (hmem hs)

/-- A halted CPU stays halted, and a running CPU halts only by retiring HLT. -/
theorem step_halts {m m' : Machine} {keys : BitVec 5} {s : State} {r : retirement}
    (h : (step keys).run (m.within s) = .ok r (m'.within s)) :
    (m.halted = true → m'.halted = true) ∧
      (m.halted = false → m'.halted = true → decode (m.fetch keys) = some (.HLT ())) := by
  cases step_cases h with
  | stopped hh => simp [hh]
  | illegal hh => simp [hh]
  | retired insn hh hd _ _ _ hne =>
    refine ⟨by simp [hh], fun _ h' => ?_⟩
    by_cases hi : insn = .HLT ()
    · simpa [hi] using hd
    · simp [hne hi] at h'

/-- A running CPU retires every instruction other than BZ, BN, JMP, CALL and RET with PC set to
(PC + 2) mod 2048. -/
theorem step_sequential {m : Machine} (keys : BitVec 5) (s : State) (hrun : m.halted = false)
    {insn : instruction} (hd : decode (m.fetch keys) = some insn) (hn : ¬ Branches insn) :
    ∃ m' : Machine, (step keys).run (m.within s) = .ok (.Retired ()) (m'.within s) ∧
      m'.pc.toNat = (m.pc.toNat + 2) % 2048 := by
  obtain ⟨r, m', hall, hcase⟩ := step_spec m keys
  cases hcase with
  | stopped hh => simp [hh] at hrun
  | illegal _ hd' => simp [hd] at hd'
  | retired insn' _ hd' _ _ _ _ _ hpc =>
    obtain rfl : insn' = insn := Option.some.inj (hd'.symm.trans hd)
    exact ⟨m', hall s, by rw [hpc hn, pc_mask_add_two]⟩

/-! ## What the proofs rely on -/

open Lean Elab Command in
/-- `#standard_axioms t₁ t₂ …` fails unless the theorems depend only on Lean's standard axioms: no
unfinished proof, and nothing a compiler or a SAT solver has to be trusted for. -/
elab "#standard_axioms " ids:ident+ : command => do
  let names ← ids.mapM fun id => liftCoreM (realizeGlobalConstNoOverloadWithInfo id)
  let (_, state) := ((names.forM CollectAxioms.collect).run (← getEnv)).run {}
  for ax in state.axioms do
    unless [``propext, ``Classical.choice, ``Quot.sound].contains ax do
      throwError "these theorems depend on the axiom {ax}"

#standard_axioms encode_opcode step_progress step_progress_of_complete
  step_fails_without_registers
  step_preserves_wf reset_wf sail_model_init_wf steps_safe power_on_safe step_halted
  decode_encode encode_injective decode_eq_none_iff encdec_backwards_matches_run
  encdec_backwards_run
  step_illegal step_illegal_pc step_illegal_of_opcode
  execute_memory execute_halted execute_hlt retire_sequential step_memory step_halts
  step_sequential

end Tara.Proofs
