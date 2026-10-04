/* Test fixtures only. Production instruction semantics does not pass snapshots
 * or transition records. These helpers install state, run the native Sail
 * model, and collect observations so regression cases remain easy to compare.
 */
$include "../tara.sail"

struct state = {
  regs : regfile,
  pc : word,
  mem : memory,
  halted : bool
}

struct transition = { outcome : outcome, state : state, events : events }

val zero_state : unit -> state
function zero_state() = struct {
  regs = vector_init(8, 0x0000), pc = 0x0000,
  mem = vector_init(2048, 0x00), halted = false
}

val read_reg : (state, regidx) -> word
function read_reg(s, r) = s.regs[unsigned(r)]

val snapshot : unit -> state
function snapshot() = struct { regs = GPR, pc = PC, mem = MEM, halted = HALTED }

val install_state : state -> unit
function install_state(s) = {
  GPR = s.regs;
  PC = s.pc;
  MEM = s.mem;
  HALTED = s.halted
}

val observe : outcome -> transition
function observe(result) = struct { outcome = result, state = snapshot(), events = Events }

val execute_from : (environment, state, instruction) -> transition
function execute_from(env, s, insn) = {
  install_state(s);
  let result = run_instruction(env, insn);
  observe(result)
}

val step_from : (environment, state) -> transition
function step_from(env, s) = {
  install_state(s);
  let result = step(env);
  observe(result)
}

val step_from_with : (environment, opcode_table, state) -> transition
function step_from_with(env, table, s) = {
  install_state(s);
  let result = step_with(env, table);
  observe(result)
}

/* Raw fixture loading deliberately bypasses devices; not a CPU store. */
val seed_word : (state, word, word) -> state
function seed_word(s, addr, value) = {
  var result : state = s;
  let following : word = addr + 0x0001;
  result.mem[unsigned(addr[10..0])] = value[15..8];
  result.mem[unsigned(following[10..0])] = value[7..0];
  result
}
