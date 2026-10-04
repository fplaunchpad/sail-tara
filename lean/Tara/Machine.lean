import Tara

/-!
# Machine states and how the generated monad acts on them

The generated model keeps its registers in Sail's `SequentialState`: a map from `Register` to
values, next to bookkeeping that TARA never touches. A machine state gives a value to every
register of `model/machine.sail`, and `Machine.within` puts one in a Sail state. Every Sail state
that has all the registers is of this form (`State.exists_machine`).

The model's functions only read and write registers, so running one on `m.within s` computes: the
lemmas below give the run of each primitive, and `simp` does the rest.
-/

open Tara Tara.Functions Tara.Register Sail.ConcurrencyInterfaceV1

namespace Tara.Proofs

/-- Sail's state for the generated model: the registers, and bookkeeping the model never uses. -/
abbrev State := SequentialState RegisterType trivialChoiceSource

/-- Sail's map from each register to its value. -/
abbrev RegMap := Std.ExtDHashMap Register RegisterType

/-- A machine state: the value of every register of the model (`model/machine.sail`). -/
structure Machine where
  /-- The registers R0 to R7. -/
  gpr : Vector (BitVec 16) 8
  /-- The program counter. -/
  pc : BitVec 16
  /-- The 2 KB memory. -/
  mem : Vector (BitVec 8) 2048
  /-- The halt latch. -/
  halted : Bool
  /-- The five input lines, as the current step holds them. -/
  keys : BitVec 5
  /-- The successor PC proposed by the current instruction (driver scratch). -/
  nextPC : BitVec 16

/-- Write every register of `m` into the register map `r`. -/
def Machine.overwrite (m : Machine) (r : RegMap) : RegMap :=
  (((((r.insert GPR m.gpr).insert PC m.pc).insert MEM m.mem).insert HALTED m.halted).insert
    KEYS m.keys).insert Register.nextPC m.nextPC

/-- The registers of `m` as Sail's register map. -/
def Machine.regs (m : Machine) : RegMap := m.overwrite ∅

/-- `s` with its registers replaced by those of `m`. -/
def Machine.within (m : Machine) (s : State) : State := { s with regs := m.regs }

/-! ## Registers in the register map -/

section
local macro "get_simp" : tactic =>
  `(tactic| simp [Machine.regs, Machine.overwrite, Std.ExtDHashMap.get?_insert])

theorem Machine.get?_GPR (m : Machine) : m.regs.get? GPR = some m.gpr := by get_simp
theorem Machine.get?_PC (m : Machine) : m.regs.get? PC = some m.pc := by get_simp
theorem Machine.get?_MEM (m : Machine) : m.regs.get? MEM = some m.mem := by get_simp
theorem Machine.get?_HALTED (m : Machine) : m.regs.get? HALTED = some m.halted := by get_simp
theorem Machine.get?_KEYS (m : Machine) : m.regs.get? KEYS = some m.keys := by get_simp
theorem Machine.get?_nextPC (m : Machine) :
    m.regs.get? Register.nextPC = some m.nextPC := by get_simp
end

section
local macro "insert_simp" : tactic =>
  `(tactic| (apply Std.ExtDHashMap.ext_get?; intro k; cases k <;>
     simp [Machine.regs, Machine.overwrite, Std.ExtDHashMap.get?_insert]))

theorem Machine.insert_GPR (m : Machine) (v : Vector (BitVec 16) 8) :
    m.regs.insert GPR v = { m with gpr := v }.regs := by insert_simp
theorem Machine.insert_PC (m : Machine) (v : BitVec 16) :
    m.regs.insert PC v = { m with pc := v }.regs := by insert_simp
theorem Machine.insert_MEM (m : Machine) (v : Vector (BitVec 8) 2048) :
    m.regs.insert MEM v = { m with mem := v }.regs := by insert_simp
theorem Machine.insert_HALTED (m : Machine) (v : Bool) :
    m.regs.insert HALTED v = { m with halted := v }.regs := by insert_simp
theorem Machine.insert_KEYS (m : Machine) (v : BitVec 5) :
    m.regs.insert KEYS v = { m with keys := v }.regs := by insert_simp
theorem Machine.insert_nextPC (m : Machine) (v : BitVec 16) :
    m.regs.insert Register.nextPC v = { m with nextPC := v }.regs := by insert_simp
end

/-- Writing every register leaves exactly the registers written, whatever the map held before. -/
theorem Machine.regs_overwrite (r : RegMap) (m : Machine) : m.overwrite r = m.regs := by
  apply Std.ExtDHashMap.ext_get?
  intro x
  cases x <;> simp [Machine.regs, Machine.overwrite, Std.ExtDHashMap.get?_insert]

/-- A Sail state determines the machine inside it. -/
theorem Machine.within_inj {m m' : Machine} {s : State} (h : m.within s = m'.within s) :
    m = m' := by
  have h' : m.regs = m'.regs := congrArg SequentialState.regs h
  have hg := congrArg (·.get? GPR) h'
  have hp := congrArg (·.get? PC) h'
  have hm := congrArg (·.get? MEM) h'
  have hh := congrArg (·.get? HALTED) h'
  have hk := congrArg (·.get? KEYS) h'
  have hn := congrArg (·.get? Register.nextPC) h'
  simp only [Machine.get?_GPR, Machine.get?_PC, Machine.get?_MEM, Machine.get?_HALTED,
    Machine.get?_KEYS, Machine.get?_nextPC, Option.some.injEq] at hg hp hm hh hk hn
  cases m
  cases m'
  simp_all

/-! ## The run of a register read or write

Reading a register of `m.within s` gives the value in `m` and leaves the state alone; writing one
gives `m` with that register changed. The reads spell out the value's type: the simplifier indexes
it, and it does not see through `RegisterType r`. -/

theorem run_readReg_of_some {r : Register} {v : RegisterType r} {s : State}
    (h : s.regs.get? r = some v) : (readReg r).run s = .ok v s := by
  simp [readReg, PreSail.readReg, h]

/-- `s` with its register map transformed by `f`. -/
def State.mapRegs (f : RegMap → RegMap) (s : State) : State := { s with regs := f s.regs }

/-- Writes in a row stay one small update of the register map, not a growing tower of states. -/
@[simp] theorem State.mapRegs_mapRegs (f g : RegMap → RegMap) (s : State) :
    (s.mapRegs f).mapRegs g = s.mapRegs (fun regs => g (f regs)) := rfl

theorem run_writeReg (r : Register) (v : RegisterType r) (s : State) :
    (writeReg r v).run s = .ok () (s.mapRegs (fun regs => regs.insert r v)) := by
  simp [writeReg, PreSail.writeReg, State.mapRegs]

section
variable (m : Machine) (s : State)

@[simp] theorem run_readReg_GPR :
    @EStateM.run _ _ (Vector (BitVec 16) 8) (readReg GPR) (m.within s) = .ok m.gpr (m.within s) :=
  run_readReg_of_some (by simp [Machine.within, Machine.get?_GPR])
@[simp] theorem run_readReg_PC :
    @EStateM.run _ _ (BitVec 16) (readReg PC) (m.within s) = .ok m.pc (m.within s) :=
  run_readReg_of_some (by simp [Machine.within, Machine.get?_PC])
@[simp] theorem run_readReg_MEM :
    @EStateM.run _ _ (Vector (BitVec 8) 2048) (readReg MEM) (m.within s) =
      .ok m.mem (m.within s) :=
  run_readReg_of_some (by simp [Machine.within, Machine.get?_MEM])
@[simp] theorem run_readReg_HALTED :
    @EStateM.run _ _ Bool (readReg HALTED) (m.within s) = .ok m.halted (m.within s) :=
  run_readReg_of_some (by simp [Machine.within, Machine.get?_HALTED])
@[simp] theorem run_readReg_KEYS :
    @EStateM.run _ _ (BitVec 5) (readReg KEYS) (m.within s) = .ok m.keys (m.within s) :=
  run_readReg_of_some (by simp [Machine.within, Machine.get?_KEYS])
@[simp] theorem run_readReg_nextPC :
    @EStateM.run _ _ (BitVec 16) (readReg Register.nextPC) (m.within s) =
      .ok m.nextPC (m.within s) :=
  run_readReg_of_some (by simp [Machine.within, Machine.get?_nextPC])

@[simp] theorem run_writeReg_GPR (v : Vector (BitVec 16) 8) :
    (writeReg GPR v).run (m.within s) = .ok () ({ m with gpr := v }.within s) := by
  simp [run_writeReg, State.mapRegs, Machine.within, Machine.insert_GPR]
@[simp] theorem run_writeReg_PC (v : BitVec 16) :
    (writeReg PC v).run (m.within s) = .ok () ({ m with pc := v }.within s) := by
  simp [run_writeReg, State.mapRegs, Machine.within, Machine.insert_PC]
@[simp] theorem run_writeReg_MEM (v : Vector (BitVec 8) 2048) :
    (writeReg MEM v).run (m.within s) = .ok () ({ m with mem := v }.within s) := by
  simp [run_writeReg, State.mapRegs, Machine.within, Machine.insert_MEM]
@[simp] theorem run_writeReg_HALTED (v : Bool) :
    (writeReg HALTED v).run (m.within s) = .ok () ({ m with halted := v }.within s) := by
  simp [run_writeReg, State.mapRegs, Machine.within, Machine.insert_HALTED]
@[simp] theorem run_writeReg_KEYS (v : BitVec 5) :
    (writeReg KEYS v).run (m.within s) = .ok () ({ m with keys := v }.within s) := by
  simp [run_writeReg, State.mapRegs, Machine.within, Machine.insert_KEYS]
@[simp] theorem run_writeReg_nextPC (v : BitVec 16) :
    (writeReg Register.nextPC v).run (m.within s) =
      .ok () ({ m with nextPC := v }.within s) := by
  simp [run_writeReg, State.mapRegs, Machine.within, Machine.insert_nextPC]
end

/-! ## The rest of the monad's operations

The core library gives the run of `pure`, `bind`, `get`, `set` and `modify`. The generated code
also uses `<$>` and conditionals. -/

@[simp] theorem run_map {ε σ α β : Type} (f : α → β) (x : EStateM ε σ α) (s : σ) :
    EStateM.run (f <$> x) s = match EStateM.run x s with
      | .ok a s' => .ok (f a) s'
      | .error e s' => .error e s' := rfl

@[simp] theorem run_ite {ε σ α : Type} (c : Prop) [Decidable c] (a b : EStateM ε σ α) (s : σ) :
    EStateM.run (if c then a else b) s = if c then EStateM.run a s else EStateM.run b s := by
  split <;> rfl

/-! ## The memory bus

The byte bus returns the input lines at the input port and RAM elsewhere. The word bus is two byte
reads, high byte first, that ignore address bit 0. These are the model's `read_byte` and
`read_word` as functions of a machine. -/

/-- The byte the model's `read_byte` returns. -/
def Machine.readByte (m : Machine) (addr : BitVec 16) : BitVec 8 :=
  if Sail.BitVec.extractLsb addr 10 0 = input_port then 0#3 +++ m.keys
  else m.mem[Sail.BitVec.toNatInt (Sail.BitVec.extractLsb addr 10 0)]!

/-- The word the model's `read_word` returns. -/
def Machine.readWord (m : Machine) (addr : BitVec 16) : BitVec 16 :=
  m.readByte (Sail.BitVec.extractLsb addr 15 1 +++ 0#1) +++
    m.readByte (Sail.BitVec.extractLsb addr 15 1 +++ 1#1)

@[simp] theorem run_read_byte (m : Machine) (s : State) (addr : BitVec 16) :
    (read_byte addr).run (m.within s) = .ok (m.readByte addr) (m.within s) := by
  by_cases h : Sail.BitVec.extractLsb addr 10 0 = input_port <;>
    simp [read_byte, Machine.readByte, h]

@[simp] theorem run_read_word (m : Machine) (s : State) (addr : BitVec 16) :
    (read_word addr).run (m.within s) = .ok (m.readWord addr) (m.within s) := by
  simp [read_word, Machine.readWord]

/-! ## Undefined values

The model's choice source resolves every undefined value to zero or false and keeps no state, and
`sail_model_init` is the only place the model asks for one. -/

theorem run_undefined_bitvector (n : Nat) (s : State) :
    (undefined_bitvector n).run s = .ok 0#n s := rfl

theorem run_undefined_bool (s : State) : (undefined_bool ()).run s = .ok false s := rfl

/-! ## Machine states are the complete Sail states -/

/-- A Sail state with a value for every register: the states the model runs from. A state that
lacks one is not a machine state: the model's first read of it fails with `Unreachable`. -/
def State.Complete (s : State) : Prop := ∀ r : Register, (s.regs.get? r).isSome

/-- Every complete Sail state is a machine state in its Sail surroundings. -/
theorem State.exists_machine {s : State} (hs : s.Complete) : ∃ m : Machine, s = m.within s := by
  obtain ⟨g, hg⟩ := Option.isSome_iff_exists.mp (hs GPR)
  obtain ⟨p, hp⟩ := Option.isSome_iff_exists.mp (hs PC)
  obtain ⟨r, hr⟩ := Option.isSome_iff_exists.mp (hs MEM)
  obtain ⟨h, hh⟩ := Option.isSome_iff_exists.mp (hs HALTED)
  obtain ⟨k, hk⟩ := Option.isSome_iff_exists.mp (hs KEYS)
  obtain ⟨n, hn⟩ := Option.isSome_iff_exists.mp (hs Register.nextPC)
  refine ⟨⟨g, p, r, h, k, n⟩, ?_⟩
  suffices s.regs = Machine.regs ⟨g, p, r, h, k, n⟩ by
    cases s; simp_all [Machine.within]
  apply Std.ExtDHashMap.ext_get?
  intro x
  cases x <;> simp_all [Machine.regs, Machine.overwrite, Std.ExtDHashMap.get?_insert]

end Tara.Proofs
