/* One attempt, one input snapshot. These are the public retirement drivers.
 * Only GPR, PC, MEM and HALTED are architectural. Events, Platform and nextPC
 * are driver bookkeeping, excluded from the unchanged-architecture contract.
 */
function begin_attempt(env : environment) -> unit = {
  Platform = env;
  Events = vector_init(4, None())
}

/* Internal worker, called only after the halted check. On a boundary, execute
 * has not written architectural state. Sail exceptions provide NO rollback.
 * A successful HLT still reaches the PC assignment below and retires once. */
function retire(insn : instruction) -> outcome = {
  nextPC = PC + 0x0002;
  execute(insn);
  PC = nextPC;
  Retired()
}

/* Decoded instructions have no fetch and do not require an aligned PC. */
function run_instruction(env : environment, insn : instruction) -> outcome = {
  begin_attempt(env);
  if HALTED then return Stopped();
  try { retire(insn) } catch {
    SpecificationBoundary(reason) => NeedsSpecification(reason)
  }
}

/* Fetch from LIVE unified memory. Keep fetch observations even if decode or
 * data alignment reaches a boundary. Check the opcode table before fetching:
 * an invalid table must not cause an input read at a memory-mapped PC. */
function step_with(env : environment, table : opcode_table) -> outcome = {
  begin_attempt(env);
  if HALTED then return Stopped();
  if PC[0] == bitone then return NeedsSpecification(OddInstructionFetch(PC));
  try {
    check_opcodes(table);
    let raw = bus_read_word(PC, Fetch);
    let insn = decode_with(table, raw);
    retire(insn)
  } catch {
    SpecificationBoundary(reason) => NeedsSpecification(reason)
  }
}

function step(env : environment) -> outcome = step_with(env, evidenced_opcodes())
