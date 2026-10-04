import Tara.Machine

/-!
# What `execute` does to a machine

`execute_spec` covers all 27 instructions at once. Whatever surrounds the registers, executing an
instruction succeeds and leaves a machine that differs from the starting one only as
`ExecuteFrame` allows.
-/

namespace Tara.Proofs

open Tara Tara.Functions Tara.Register Sail.ConcurrencyInterfaceV1

/-- The instructions that store to memory. -/
def Stores : instruction → Prop
  | .STW _ | .STB _ | .PUSH _ => True
  | _ => False

/-- The instructions that choose the successor PC. Every other instruction leaves it as it was. -/
def Branches : instruction → Prop
  | .BZ _ | .BN _ | .JMP _ | .CALL _ | .RET _ => True
  | _ => False

/-- What executing `insn` from `m` leaves in `m'`: the same PC and KEYS, the same memory unless
`insn` stores, the same HALTED unless it is HLT (which sets it) and the same proposed successor PC
unless it branches. -/
structure ExecuteFrame (insn : instruction) (m m' : Machine) : Prop where
  pc : m'.pc = m.pc
  keys : m'.keys = m.keys
  mem : ¬ Stores insn → m'.mem = m.mem
  halted : insn ≠ .HLT () → m'.halted = m.halted
  hlt : insn = .HLT () → m'.halted = true
  nextPC : ¬ Branches insn → m'.nextPC = m.nextPC

/-- Prove one instruction's case. The machine it leaves is found by running it, so the witness is
left for unification (`rfl`) to fill in; the frame is then checked on the result. The run uses the
hypotheses in context: the outcome of a branch condition, where there is one. -/
local macro "exec_case" : tactic =>
  `(tactic| (
    refine ⟨?_, fun s => ?run, ?frame⟩
    case run =>
      simp [*, execute, execute_NOP, execute_HLT, execute_MOV, execute_LIL, execute_LIH,
        execute_LDW, execute_STW, execute_LDB, execute_STB, execute_ADD, execute_SUB,
        execute_ADDI, execute_MUL, execute_AND, execute_OR, execute_XOR, execute_NOT,
        execute_SHL, execute_SHR, execute_SLT, execute_BZ, execute_BN, execute_JMP, execute_CALL,
        execute_RET, execute_PUSH, execute_POP, rX, wX, write_word, write_byte]
      rfl
    case frame => constructor <;> simp [Stores, Branches]))

/-- Executing an instruction succeeds, whatever surrounds the registers, and leaves a machine that
differs from the starting one only as `ExecuteFrame` allows. -/
theorem execute_spec (insn : instruction) (m : Machine) :
    ∃ m' : Machine,
      (∀ s, (execute insn).run (m.within s) = .ok () (m'.within s)) ∧ ExecuteFrame insn m m' := by
  cases insn
  case SLT a =>
    obtain ⟨rd, rs1, rs2⟩ := a
    by_cases m.gpr[Sail.BitVec.toNatInt rs1]!.toInt < m.gpr[Sail.BitVec.toNatInt rs2]!.toInt
      <;> exec_case
  case BZ a =>
    obtain ⟨rs, off⟩ := a
    by_cases m.gpr[Sail.BitVec.toNatInt rs]! = 0#16 <;> exec_case
  case BN a =>
    obtain ⟨rs, off⟩ := a
    by_cases Sail.BitVec.access m.gpr[Sail.BitVec.toNatInt rs]! 15 = 1#1 <;> exec_case
  all_goals exec_case

/-- `execute_spec` for an execution known to run from `m` to `m'`. -/
theorem execute_frame {insn : instruction} {m m' : Machine} {s : State}
    (h : (execute insn).run (m.within s) = .ok () (m'.within s)) : ExecuteFrame insn m m' := by
  obtain ⟨m₀, hall, hframe⟩ := execute_spec insn m
  obtain ⟨-, rfl⟩ := Machine.ok_within_inj ((hall s).symm.trans h)
  exact hframe

end Tara.Proofs
