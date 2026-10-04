/* Drivers. Each call takes the five input lines, held for its duration, and
 * retires at most one instruction. A halted CPU does nothing until reset.
 */
union retirement = {
  Retired : unit,
  Stopped : unit,
  Illegal : word
}

/* The successor defaults to PC + 2; execute may replace it before the commit. */
function retire(insn : instruction) -> retirement = {
  nextPC = PC + 0x0002;
  execute(insn);
  PC = pc_mask(nextPC);
  Retired()
}

/* Execute a decoded instruction as if it had been fetched from PC. */
val run_instruction : (bits(5), instruction) -> retirement

function run_instruction(keys, insn) =
  if HALTED then Stopped() else {
    KEYS = keys;
    retire(insn)
  }

/* Fetch from live memory, decode and execute. The fetch steps that precede
 * decoding advance PC for every word; an unassigned opcode stops there. */
val step : bits(5) -> retirement

function step(keys) =
  if HALTED then Stopped() else {
    KEYS = keys;
    let raw = read_word(PC);
    match decode(raw) {
      Some(insn) => retire(insn),
      None() => {
        PC = pc_mask(PC + 0x0002);
        Illegal(raw)
      }
    }
  }

/* The reset button: "clears halted state, and restarts from PC 0".
 * Registers and memory keep their values. */
val reset : unit -> unit

function reset() = {
  PC = 0x0000;
  HALTED = false
}
