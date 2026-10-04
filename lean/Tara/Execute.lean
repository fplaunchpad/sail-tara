import Tara.Machine

/-!
# What `execute` does to a machine

`execute_spec` covers all 27 instructions at once. Whatever surrounds the registers, executing an
instruction succeeds and leaves a machine that differs from the starting one only in the ways the
frame conditions allow.
-/

namespace Tara.Proofs

open Tara Tara.Functions Tara.Register Sail.ConcurrencyInterfaceV1

/-- The instructions that store to memory. -/
def Stores : instruction → Prop
  | .STW _ | .STB _ | .PUSH _ => True
  | _ => False

/-- The instructions that choose the successor PC. Every other instruction proposes PC + 2. -/
def Branches : instruction → Prop
  | .BZ _ | .BN _ | .JMP _ | .CALL _ | .RET _ => True
  | _ => False

/-- Unfold an instruction's `execute` on `m.within s` into the machine it leaves. -/
local macro "exec_simp" : tactic =>
  `(tactic| simp [execute, execute_NOP, execute_HLT, execute_MOV, execute_LIL, execute_LIH,
      execute_LDW, execute_STW, execute_LDB, execute_STB, execute_ADD, execute_SUB, execute_ADDI,
      execute_MUL, execute_AND, execute_OR, execute_XOR, execute_NOT, execute_SHL, execute_SHR,
      execute_SLT, execute_BZ, execute_BN, execute_JMP, execute_CALL, execute_RET, execute_PUSH,
      execute_POP, rX, wX, write_word, write_byte])

/-- Prove one instruction's case. The machine it leaves is found by running it, so the witness is
left for unification (`rfl`) to fill in; the frame facts are then checked on the result. -/
local macro "exec_case" : tactic =>
  `(tactic| (refine' ⟨_, fun s => _, _⟩
             rotate_left
             · exec_simp; rfl
             · simp [Stores, Branches]))

/-- The same, for an instruction whose result depends on a condition that `h` decides. -/
local macro "exec_case_with" h:ident : tactic =>
  `(tactic| (refine' ⟨_, fun s => _, _⟩
             rotate_left
             · simp [execute, execute_SLT, execute_BZ, execute_BN, rX, wX, $h:ident]; rfl
             · simp [Stores, Branches]))

set_option maxHeartbeats 400000 in
/-- Executing an instruction succeeds, whatever surrounds the registers, and leaves a machine `m'`
that has the same PC and KEYS, the same memory unless the instruction stores, the same HALTED unless
it is HLT (which sets it) and the same proposed successor PC unless it branches. -/
theorem execute_spec (insn : instruction) (m : Machine) :
    ∃ m' : Machine, (∀ s, (execute insn).run (m.within s) = .ok () (m'.within s)) ∧
      m'.pc = m.pc ∧ m'.keys = m.keys ∧
      (¬ Stores insn → m'.mem = m.mem) ∧
      (insn ≠ .HLT () → m'.halted = m.halted) ∧ (insn = .HLT () → m'.halted = true) ∧
      (¬ Branches insn → m'.nextPC = m.nextPC) := by
  cases insn with
  | NOP _ => exec_case
  | HLT _ => exec_case
  | MOV a => obtain ⟨rd, rs⟩ := a; exec_case
  | LIL a => obtain ⟨rd, imm⟩ := a; exec_case
  | LIH a => obtain ⟨rd, imm⟩ := a; exec_case
  | LDW a => obtain ⟨rd, base, off⟩ := a; exec_case
  | STW a => obtain ⟨rs, base, off⟩ := a; exec_case
  | LDB a => obtain ⟨rd, base, off⟩ := a; exec_case
  | STB a => obtain ⟨rs, base, off⟩ := a; exec_case
  | ADD a => obtain ⟨rd, rs1, rs2⟩ := a; exec_case
  | SUB a => obtain ⟨rd, rs1, rs2⟩ := a; exec_case
  | ADDI a => obtain ⟨rd, imm⟩ := a; exec_case
  | MUL a => obtain ⟨rd, rs1, rs2⟩ := a; exec_case
  | AND a => obtain ⟨rd, rs1, rs2⟩ := a; exec_case
  | OR a => obtain ⟨rd, rs1, rs2⟩ := a; exec_case
  | XOR a => obtain ⟨rd, rs1, rs2⟩ := a; exec_case
  | NOT a => obtain ⟨rd, rs⟩ := a; exec_case
  | SHL a => obtain ⟨rd, shamt⟩ := a; exec_case
  | SHR a => obtain ⟨rd, shamt⟩ := a; exec_case
  | SLT a =>
    obtain ⟨rd, rs1, rs2⟩ := a
    by_cases hc : m.gpr[Sail.BitVec.toNatInt rs1]!.toInt < m.gpr[Sail.BitVec.toNatInt rs2]!.toInt
    <;> exec_case_with hc
  | BZ a =>
    obtain ⟨rs, off⟩ := a
    by_cases hc : m.gpr[Sail.BitVec.toNatInt rs]! = 0#16 <;> exec_case_with hc
  | BN a =>
    obtain ⟨rs, off⟩ := a
    by_cases hc : Sail.BitVec.access m.gpr[Sail.BitVec.toNatInt rs]! 15 = 1#1
    <;> exec_case_with hc
  | JMP _ => exec_case
  | CALL _ => exec_case
  | RET _ => exec_case
  | PUSH _ => exec_case
  | POP _ => exec_case

/-- `execute_spec` for an execution known to run from `m` to `m'`: what it leaves alone. -/
theorem execute_frame {insn : instruction} {m m' : Machine} {s : State}
    (h : (execute insn).run (m.within s) = .ok () (m'.within s)) :
    m'.pc = m.pc ∧ m'.keys = m.keys ∧
      (¬ Stores insn → m'.mem = m.mem) ∧
      (insn ≠ .HLT () → m'.halted = m.halted) ∧ (insn = .HLT () → m'.halted = true) ∧
      (¬ Branches insn → m'.nextPC = m.nextPC) := by
  obtain ⟨m₀, hall, hframe⟩ := execute_spec insn m
  rw [hall s] at h
  obtain ⟨-, hm⟩ := EStateM.Result.ok.inj h
  obtain rfl := Machine.within_inj hm
  exact hframe

end Tara.Proofs
