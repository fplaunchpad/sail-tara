/* Host interface of the C and OCaml emulators: state access, stepping, and
 * text. All text is formatted here, in Sail, so both emulators print the same
 * bytes.
 */

$include "state.sail"
$include "../model/syntax.sail"

/* Keep the interface in the C output, which drops unreachable functions. */
$option --c-preserve host_reset
$option --c-preserve host_peek
$option --c-preserve host_poke
$option --c-preserve host_reg
$option --c-preserve host_pc
$option --c-preserve host_halted
$option --c-preserve host_pixel
$option --c-preserve host_step
$option --c-preserve host_disasm
$option --c-preserve host_trace
$option --c-preserve host_dump

function hex_digit(n : bits(4)) -> string = match n {
    0x0 => "0",
    0x1 => "1",
    0x2 => "2",
    0x3 => "3",
    0x4 => "4",
    0x5 => "5",
    0x6 => "6",
    0x7 => "7",
    0x8 => "8",
    0x9 => "9",
    0xa => "a",
    0xb => "b",
    0xc => "c",
    0xd => "d",
    0xe => "e",
    0xf => "f",
}

function hex8(b : byte) -> string = hex_digit(b[7 .. 4]) ^ hex_digit(b[3 .. 0])

function hex16(w : word) -> string = hex8(w[15 .. 8]) ^ hex8(w[7 .. 0])

val host_disasm : bits(16) -> string

function host_disasm(w) = if encdec_backwards_matches(w) then {
    assembly(encdec(w))
} else {
    "illegal"
}

/* The step just taken: its PC and word, the registers after it, and its
 * assembly. For example: 0014 0800 0000 0000 0037 0059 0059 0000 0037 0000 HLT */
val host_trace : unit -> string

function host_trace() = {
    var line = hex16(trace_pc) ^ " " ^ hex16(trace_word);
    foreach (r from 0 to 7) {
        line = line ^ " " ^ hex16(GPR[r])
    };
    line ^ " " ^ host_disasm(trace_word)
}

/* The final state, one field per line; the memory as 4096 hex digits. */
val host_dump : unit -> string

function host_dump() = {
    var text = "pc 0x" ^ hex16(PC) ^ "\n";
    foreach (r from 0 to 7) {
        text = text ^ "r" ^ dec_str(r) ^ " 0x" ^ hex16(GPR[r]) ^ "\n"
    };
    var memory = "";
    foreach (a from 0 to 2047) {
        memory = memory ^ hex8(MEM[a])
    };
    text ^ "mem " ^ memory ^ "\n"
}

/* The generated C's model_main calls main; the emulators bring their own. */
val main : unit -> unit

function main() = ()
