/* Drivers. Each call takes the five input lines, held for its duration, and
 * retires at most one instruction. A halted CPU does nothing until reset.
 */

/*!
== Execution */
$anchor section_execution

/*! The drivers run one instruction per call. `step` and `run_instruction` take the five input lines
as their first argument and hold them for the duration of the call. A driver reports what happened
with a `retirement`.

- `Retired`: an instruction ran to completion. `HLT` retires like any other instruction; it also
sets the halt latch.
- `Stopped`: the CPU is halted and nothing happened: no fetch, no input latched, no state changed.
- `Illegal`: the fetched word has an unassigned opcode, 27 to 31; the payload is that word. The
fetch advanced PC past the word, and registers, memory and the halt latch are unchanged.
 */
$anchor drivers

union retirement = {
  Retired : unit,
  Stopped : unit,
  Illegal : word
}

/*! Retires a decoded instruction. The successor defaults to `PC + 2`; `execute` may replace it in
`nextPC`, and the result, masked to 11 bits, becomes PC. An instruction therefore sees PC as its own
address, while the RTL has already incremented PC by the time the instruction executes: the
PC-relative targets of the instruction set are written accordingly.
 */
function retire(insn : instruction) -> retirement = {
    nextPC = PC + 0x0002;
    execute(insn);
    PC = pc_mask(nextPC);
    Retired()
}

/*! Executes an instruction that is already decoded, as if it had been fetched from PC, without
placing it in memory. It does no fetch; a halted CPU does nothing, as for `step`.
 */
val run_instruction : (bits(5), instruction) -> retirement

function run_instruction(keys, insn) =
    if HALTED then {
        Stopped()
    } else {
        KEYS = keys;
        retire(insn)
    }

/*! The model of the processor: it runs the next instruction from memory. A halted CPU returns
`Stopped`. Otherwise `step` latches the input lines in `KEYS`, fetches the word at PC with
`read_word`, decodes it and retires the instruction. The fetch is an ordinary word read: it ignores
bit 0 of PC, it sees the input port if it covers 0x5FF, and it sees the stores of earlier
instructions, which is how self-modifying code works. An unassigned opcode, 27 to 31, advances PC to
`pc_mask(PC + 2)`, as the fetch steps of the RTL do for every word, and returns `Illegal` with the
word. The model does not halt the CPU there: what the hardware does next is not published, so the
host decides.
 */
val step : bits(5) -> retirement

function step(keys) =
    if HALTED then {
        Stopped()
    } else {
        KEYS = keys;
        let raw = read_word(PC);
        match decode(raw) {
            Some(insn) => retire(insn),
            None() => {
                PC = pc_mask(PC + 0x0002);
                Illegal(raw)
            },
        }
    }

/*! The reset button: "clears halted state, and restarts from PC 0". Registers and memory keep their
values.
 */
val reset : unit -> unit

function reset() = {
    PC = 0x0000;
    HALTED = false
}
