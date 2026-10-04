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

let subcommands = [ "run", run_command; "play", play_command; "disasm", disasm_command ]
let command = Command.group ~summary:"Run TARA programs on the Sail model" subcommands
let subcommand_names = List.map subcommands ~f:fst

(* Core resolves command prefixes; keep the public subcommand names exact like tara-c. *)
let reject_subcommand_prefix () =
  let arguments = Sys.get_argv () in
  let help_options = [ "--help"; "-help"; "-?"; "-h" ] in
  let candidate_index =
    if Array.length arguments > 1 && List.mem help_options arguments.(1) ~equal:String.equal
    then 2
    else 1
  in
  if Array.length arguments > candidate_index
  then (
    let name = arguments.(candidate_index) in
    let exact = List.mem subcommand_names name ~equal:String.equal in
    let prefix = List.exists subcommand_names ~f:(String.is_prefix ~prefix:name) in
    if (not exact) && prefix && not (String.is_empty name)
    then (
      Out_channel.output_string
        stderr
        [%string "tara-ocaml: '%{name}' is not a subcommand: run, play or disasm\n"];
      Stdlib.exit 1))
;;

let () =
  reject_subcommand_prefix ();
  Command_unix.run command
;;
