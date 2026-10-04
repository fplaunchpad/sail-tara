/* Test fixtures only: install a state, run the native Sail model, and
 * snapshot the result so regression cases compare plain values.
 */
$include "../model/syntax.sail"

struct state = {
  regs : regfile,
  pc : word,
  mem : memory,
  halted : bool
}

struct transition = { result : retirement, state : state }

val zero_state : unit -> state
function zero_state() = struct {
  regs = vector_init(8, 0x0000), pc = 0x0000,
  mem = vector_init(2048, 0x00), halted = false
}

val snapshot : unit -> state
function snapshot() = struct { regs = GPR, pc = PC, mem = MEM, halted = HALTED }

val install_state : state -> unit
function install_state(s) = {
  GPR = s.regs;
  PC = s.pc;
  MEM = s.mem;
  HALTED = s.halted
}

val observe : retirement -> transition
function observe(result) = struct { result = result, state = snapshot() }

val execute_from : (bits(5), state, instruction) -> transition
function execute_from(keys, s, insn) = {
  install_state(s);
  observe(run_instruction(keys, insn))
}

val step_from : (bits(5), state) -> transition
function step_from(keys, s) = {
  install_state(s);
  observe(step(keys))
}

/* Raw fixture loading of the aligned word at addr; bypasses the bus. */
val seed_word : (state, word, word) -> state
function seed_word(s, addr, value) = {
  var result : state = s;
  result.mem[unsigned(addr[10..1] @ 0b0)] = value[15..8];
  result.mem[unsigned(addr[10..1] @ 0b1)] = value[7..0];
  result
}
