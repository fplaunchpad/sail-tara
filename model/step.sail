/* The drivers: each call retires at most one instruction. */

/*!
@anchor section_execution
== Execution

@anchor drivers
The drivers run an instruction per call. `step` and `run_instruction` take the input lines, hold
them for the call, and say what happened:

- `Retired`: an instruction completed. `HLT` retires like any other.
- `Stopped`: the CPU is halted, and nothing was fetched or changed.
- `Illegal(word)`: the fetched `word` has an unassigned opcode. The fetch advanced PC past it, and
nothing else changed.
 */
union retirement = {
  Retired : unit,
  Stopped : unit,
  Illegal : word
}

/*!
@brief Retire an instruction

Retires an instruction: sets `nextPC` to `PC + 2`, executes the instruction, which may change it,
and masks it into PC. The instruction sees PC as its own address, where the RTL has already advanced
PC, so relative targets add 2 to it.
 */
function retire(insn : instruction) -> retirement = {
    nextPC = PC + 0x0002;
    execute(insn);
    PC = pc_mask(nextPC);
    Retired()
}

/*!
@brief Run a decoded instruction

Executes a decoded instruction as if it had been fetched from PC, without a fetch. Like `step`, it
does nothing while the CPU is halted.
 */
val run_instruction : (bits(5), instruction) -> retirement

function run_instruction(keys, insn) =
    if HALTED then {
        Stopped()
    } else {
        KEYS = keys;
        retire(insn)
    }

/*!
@brief Fetch, decode and retire

Runs the next instruction:

- If the CPU is halted, it returns `Stopped`.
- Otherwise it latches the input lines in `KEYS`, reads `M[PC][15:0]`, decodes it
  and retires it. The fetch is an ordinary word read: it ignores bit 0 of PC, sees the input port
  when it covers `0x5FF`, and sees earlier stores, so self-modifying code works.
- An unassigned opcode advances PC to `pc_mask(PC + 2)` and returns `Illegal`. The CPU does not
  halt: what the hardware does next is not published, so the host decides.
 */
val step : bits(5) -> retirement

function step(keys) =
    if HALTED then {
        Stopped()
    } else {
        KEYS = keys;
        let raw = read_word(PC);
        if encdec_backwards_matches(raw) then {
            retire(encdec(raw))
        } else {
            PC = pc_mask(PC + 0x0002);
            Illegal(raw)
        }
    }

/*!
@brief Reset the processor

The reset button, which "clears halted state, and restarts from PC 0". Registers and memory keep
their values.
 */
val reset : unit -> unit

function reset() = {
    PC = 0x0000;
    HALTED = false
}
