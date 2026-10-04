(* TARA emulator: the OCaml build of the Sail model. Its command line matches tara-c
   (emulator/c/src/options.c): the subcommands run, play and disasm. *)

open! Import

(* A subcommand that takes what [options] parses and does something with it, which gives the exit
   status. *)
let subcommand ~summary ~readme options ~run =
  Command.basic_or_error
    ~summary
    ~readme:(fun () -> readme)
    (let%map.Command options = options in
     fun () ->
       let%map.Or_error exit_status = run options in
       if exit_status <> 0 then Stdlib.exit exit_status)
;;

let image_readme =
  {|IMAGE is .bin (bytes) or .hex (16-bit words of 1 to 4 hex digits, ';' comments), loaded from
address 0; at most 2048 bytes.|}
;;

let run_command =
  subcommand
    ~summary:"run a program to its end and print what happened"
    ~readme:
      [%string
        {|%{image_readme}

Prints the trace lines (-t), then status, steps, pc, r0-r7 and mem lines, then the framebuffer
(--framebuffer).

Exit status: 0 halted, 1 error, 3 step limit, 4 illegal opcode.|}]
    Options.run
    ~run:Batch.run
;;

let play_command =
  subcommand
    ~summary:"play a program in the terminal"
    ~readme:
      [%string
        {|%{image_readme}

Arrows or WASD drive UP, DOWN, LEFT and RIGHT, Q drives QUIT, and ESC or Ctrl-C leaves.

Exit status: 0 halted, or still running when left, 1 error, 3 step limit, 4 illegal opcode.|}]
    Options.play
    ~run:Interactive.run
;;

let disasm_command =
  subcommand
    ~summary:"print the assembly of every instruction word"
    ~readme:{|Prints a line "WWWW TEXT" for each word from 0000 to ffff.|}
    (Command.Param.return ())
    ~run:(fun () ->
      Disasm.print_all ();
      Ok 0)
;;

let command =
  Command.group
    ~summary:"Run TARA programs on the Sail model"
    [ "run", run_command; "play", play_command; "disasm", disasm_command ]
;;

let () = Command_unix.run command
