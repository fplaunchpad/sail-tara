(* TARA emulator: the OCaml build of the Sail model. Its command line matches tara-c
   (emulator/c/src/main.c). *)

open! Core

(* Do what the command line asks, and return the exit status. *)
let run (mode : Options.Mode.t) =
  match mode with
  | Disassemble ->
    Disasm.print_all ();
    Ok 0
  | Batch options -> Batch.run options
  | Interactive options -> Interactive.run options
;;

let command =
  Command.basic_or_error
    ~summary:"Run a TARA program on the Sail model"
    ~readme:(fun () ->
      {|Usage: tara-ocaml [OPTION...] IMAGE
       tara-ocaml --disasm-all

IMAGE is .bin (bytes) or .hex (16-bit words of 1 to 4 hex digits, ';' comments), loaded from
address 0; at most 2048 bytes.

A batch run prints the trace lines (-t), then status, steps, pc, r0-r7 and mem lines, then the
framebuffer (--fb).

-i plays the program in the terminal: arrows or WASD drive UP, DOWN, LEFT and RIGHT, Q drives
QUIT, and ESC or Ctrl-C leaves.

Exit status: 0 halted, 1 error, 3 step limit, 4 illegal opcode.|})
    (let%map.Command mode = Options.param in
     fun () ->
       let%bind.Or_error mode = mode in
       let%map.Or_error exit_status = run mode in
       if exit_status <> 0 then Stdlib.exit exit_status)
;;

let () = Command_unix.run command
