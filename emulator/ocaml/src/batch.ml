open! Core

module Options = struct
  type t =
    { image : Filename.t
    ; max_steps : int
    ; trace : bool
    ; keys : Keys.t
    ; key_script : Filename.t option
    ; framebuffer : bool
    }
end

let print_line line =
  Out_channel.output_string stdout line;
  Out_channel.output_char stdout '\n'
;;

(* The framebuffer as rows of '#' and '.', the top row first. *)
let print_framebuffer () =
  let framebuffer = Framebuffer.create () in
  Framebuffer.refresh framebuffer;
  for y = Framebuffer.size - 1 downto 0 do
    String.init Framebuffer.size ~f:(fun x ->
      if Framebuffer.pixel framebuffer ~x ~y then '#' else '.')
    |> sprintf "fb %s"
    |> print_line
  done
;;

let load_key_script ({ keys; key_script; _ } : Options.t) =
  match key_script with
  | None -> Ok (Key_script.constant keys)
  | Some filename -> Key_script.load filename ~initial:keys
;;

let run_to_end ({ max_steps; trace; _ } : Options.t) ~key_script =
  let run = Run.create ~max_steps in
  let rec go () =
    match Run.status run with
    | Some status -> status
    | None ->
      Run.step run ~keys:(Key_script.at key_script ~retired:(Run.retired run));
      if trace then Machine.trace () |> print_line;
      go ()
  in
  let status = go () in
  status, Run.retired run
;;

let run (options : Options.t) =
  Machine.start ();
  let%bind.Or_error () = Image.load options.image in
  let%map.Or_error key_script = load_key_script options in
  let status, steps = run_to_end options ~key_script in
  print_line [%string "status %{status#Run.Status}"];
  print_line [%string "steps %{steps#Int}"];
  Machine.dump () |> Out_channel.output_string stdout;
  if options.framebuffer then print_framebuffer ();
  Run.Status.exit_code status
;;
