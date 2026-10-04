(* TARA emulator: the OCaml build of the Sail model. Its command line matches tara-c
   (emulator/c/main.c). *)

open! Core

let default_max_steps = 1_000_000

let count =
  Command.Arg_type.create (fun text ->
    match Int.of_string_opt text with
    | Some n when n >= 0 -> n
    | _ -> raise_s [%message "expected a non-negative count" text])
;;

let command =
  Command.basic_or_error
    ~summary:"Run a TARA program on the Sail model"
    ~readme:(fun () ->
      {|IMAGE is .bin (bytes) or .hex (16-bit words, ';' comments), loaded from address 0.
The final state is printed as status, steps, pc, r0-r7 and mem lines.
Exit status: 0 halted, 1 error, 3 step limit, 4 illegal opcode.|})
    (let%map_open.Command trace = flag "-t" no_arg ~doc:" print a trace line per step"
     and max_steps =
       flag
         "-n"
         (optional_with_default default_max_steps count)
         ~doc:"MAX_STEPS stop after this many retirements (0: no limit)"
     and image = anon ("IMAGE" %: Filename_unix.arg_type) in
     fun () ->
       Machine.start ();
       let%map.Or_error () = Image.load image |> Or_error.tag ~tag:image in
       let status, steps = Run.run ~max_steps ~trace in
       print_endline [%string "status %{status#Run.Status}"];
       print_endline [%string "steps %{steps#Int}"];
       print_string (Machine.dump ());
       match Run.Status.exit_code status with
       | 0 -> ()
       | code -> Stdlib.exit code)
;;

let () = Command_unix.run command
