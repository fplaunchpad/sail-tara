open! Core

module Mode = struct
  type t =
    | Disassemble
    | Batch of Batch.Options.t
    | Interactive of Interactive.Options.t
end

let default_max_steps = 1_000_000
let default_hz = 2000
let arg_type of_string = Command.Arg_type.create (fun text -> of_string text |> Or_error.ok_exn)
let count = arg_type Number.decimal
let keys = arg_type Keys.of_string

(* The names of the flags that are set, out of each flag's name and whether it is. *)
let set flags = List.filter_map flags ~f:(fun (is_set, name) -> Option.some_if is_set name)

let cannot_combine name ~with_ =
  let flags = String.concat with_ ~sep:" " in
  Or_error.error_string [%string "%{name} cannot be combined with %{flags}"]
;;

let mode ~trace ~max_steps ~keys ~key_script ~framebuffer ~disasm_all ~interactive ~hz ~image =
  (* Playing takes no trace, framebuffer or input lines: the player gives them. A disassembly
     takes no flag at all. *)
  let batch_only =
    set
      [ trace, "--trace"
      ; framebuffer, "--fb"
      ; Option.is_some keys, "--keys"
      ; Option.is_some key_script, "--key-script"
      ]
  in
  let others =
    batch_only
    @ set
        [ Option.is_some max_steps, "--max-steps"
        ; interactive, "--interactive"
        ; Option.is_some hz, "--hz"
        ]
  in
  match disasm_all, image, interactive with
  | true, Some _, _ -> Or_error.error_string "--disasm-all takes no IMAGE"
  | true, None, _ ->
    if List.is_empty others
    then Ok Mode.Disassemble
    else cannot_combine "--disasm-all" ~with_:others
  | false, None, _ -> Or_error.error_string "expected an IMAGE"
  | false, Some image, true ->
    if List.is_empty batch_only
    then
      Ok
        (Mode.Interactive
           { image
           ; max_steps = Option.value max_steps ~default:0
           ; hz = Option.value hz ~default:default_hz
           })
    else cannot_combine "--interactive" ~with_:batch_only
  | false, Some image, false ->
    Ok
      (Mode.Batch
         { image
         ; max_steps = Option.value max_steps ~default:default_max_steps
         ; trace
         ; keys = Option.value keys ~default:Keys.none
         ; key_script
         ; framebuffer
         })
;;

let param =
  let%map_open.Command trace =
    flag "--trace" ~aliases:[ "-t" ] no_arg ~doc:" print a trace line for each step"
  and max_steps =
    flag
      "--max-steps"
      ~aliases:[ "-n" ]
      (optional count)
      ~doc:"N stop after N retirements (default 1000000; none with -i; 0: no limit)"
  and keys =
    flag "--keys" (optional keys) ~doc:"K input lines, 0-31 in decimal or 0x hex (default 0)"
  and key_script =
    flag
      "--key-script"
      (optional Filename_unix.arg_type)
      ~doc:"FILE change the input lines as it says: lines of STEP KEYS"
  and framebuffer = flag "--fb" no_arg ~doc:" print the framebuffer after the dump"
  and disasm_all =
    flag "--disasm-all" no_arg ~doc:" print the assembly of every instruction word; no IMAGE"
  and interactive = flag "--interactive" ~aliases:[ "-i" ] no_arg ~doc:" play in the terminal"
  and hz =
    flag
      "--hz"
      (optional count)
      ~doc:"N interactive instructions per second (default 2000; 0: as fast as possible)"
  and image = anon (maybe ("IMAGE" %: Filename_unix.arg_type)) in
  mode ~trace ~max_steps ~keys ~key_script ~framebuffer ~disasm_all ~interactive ~hz ~image
;;
