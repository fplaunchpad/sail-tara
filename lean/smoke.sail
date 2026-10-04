/* Executable smoke test of the Lean backend: `just lean smoke`. It runs the hardware manual's
 * Fibonacci program on the model from power-on until the CPU halts, prints the final state as the
 * emulators do (minus the memory) and compares it with the manual's. A mismatch shows the
 * expected value and fails the run.
 *
 * Sail's Lean backend turns main into the executable's main (--lean-executable). Printing is an
 * effect there, which PRINT_EFFECTS selects.
 */

$define PRINT_EFFECTS
$include "../model/tara.sail"

/* The model overloads ^ for bitwise xor; strings concatenate as well. */
overload operator ^ = {concat_str}

/* More instructions than the program retires, so a runaway program fails instead of hanging. */
let step_limit : int = 1000

/* The program from the manual, as big-endian words loaded at address 0, with its assembly. */
function load_program() -> unit = {
    write_word(0x0000, 0x1a00); /* LIL R2, 0 */
    write_word(0x0002, 0x1b01); /* LIL R3, 1 */
    write_word(0x0004, 0x1d0a); /* LIL R5, 10 */
    write_word(0x0006, 0xa505); /* loop: BZ R5, done */
    write_word(0x0008, 0x4c4c); /* ADD R4, R2, R3 */
    write_word(0x000a, 0x1260); /* MOV R2, R3 */
    write_word(0x000c, 0x1380); /* MOV R3, R4 */
    write_word(0x000e, 0x5dff); /* ADDI R5, -1 */
    write_word(0x0010, 0xb7fa); /* JMP loop */
    write_word(0x0012, 0x1640); /* done: MOV R6, R2 */
    write_word(0x0014, 0x0800) /* HLT */
}

/* The final state the manual gives: 66 instructions retire, PC is just past the HLT, F(10) is in
 * R2 and R6, F(11) in R3 and R4, and the other registers are still zero. */
let expected_steps : int = 66

let expected_pc : word = 0x0016

function expected_register(r : range(0, 7)) -> word = match r {
    2 => 0x0037,
    3 => 0x0059,
    4 => 0x0059,
    6 => 0x0037,
    _ => 0x0000,
}

/* Power-on: registers and memory zero, the CPU running from PC 0. */
function power_on() -> unit = {
    GPR = vector_init(8, 0x0000);
    MEM = vector_init(2048, 0x00);
    KEYS = 0b00000;
    reset()
}

/* How a run ends, and its name in the emulators' status line. */
enum ending = { Halted, Limited, Illegal_opcode }

function ending_name(e : ending) -> string = match e {
    Halted => "halted",
    Limited => "limit",
    Illegal_opcode => "illegal",
}

/* Step until the CPU halts, fetches an illegal opcode or step_limit instructions retire: how the
 * run ended and the number of instructions retired. */
function run_program() -> (ending, int) = {
    var retired : int = 0;
    var ended : option(ending) = None();
    while is_none(ended) do {
        if retired == step_limit then {
            ended = Some(Limited)
        } else {
            match step(0b00000) {
                Retired() => retired = retired + 1,
                Stopped() => ended = Some(Halted),
                Illegal(_) => ended = Some(Illegal_opcode),
            }
        }
    };
    match ended {
        Some(e) => (e, retired),
        None() => (Limited, retired),
    }
}

/* Print one field of the final state, with the expected value if it differs. */
function check(name : string, actual : string, expected : string) -> bool = {
    if actual == expected then {
        print_endline(name ^ " " ^ actual);
        true
    } else {
        print_endline(name ^ " " ^ actual ^ " (expected " ^ expected ^ ")");
        false
    }
}

function main() -> unit = {
    power_on();
    load_program();
    let (ended, steps) = run_program();

    var ok = check("status", ending_name(ended), ending_name(Halted));
    ok = check("steps", dec_str(steps), dec_str(expected_steps)) & ok;
    ok = check("pc", bits_str(PC), bits_str(expected_pc)) & ok;
    foreach (r from 0 to 7) {
        ok = check("r" ^ dec_str(r), bits_str(GPR[r]), bits_str(expected_register(r))) & ok
    };
    assert(ok, "the final state differs from the manual's")
}
