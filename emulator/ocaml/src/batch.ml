open! Import

module Trace = struct
  type t =
    | Print_steps
    | No_trace
end

module Framebuffer_dump = struct
  type t =
    | Print_framebuffer
    | No_framebuffer
end

module Options = struct
  type t =
    { image : Filename.t
    ; max_steps : int
    ; trace : Trace.t
    ; keys : Keys.t
    ; key_script : Filename.t option
    ; framebuffer : Framebuffer_dump.t
    }
end

let print_line line =
  Out_channel.output_string stdout line;
  Out_channel.output_char stdout '\n'
;;

(* The framebuffer as rows of '#' and '.', the top row first. *)
let print_framebuffer () =
  let framebuffer = Framebuffer.read () in
  for y = Framebuffer.size - 1 downto 0 do
    let row =
      String.init Framebuffer.size ~f:(fun x ->
        match Framebuffer.pixel framebuffer ~x ~y with
        | Lit -> '#'
        | Dark -> '.')
    in
    print_line [%string "fb %{row}"]
  done
;;

let load_key_script ({ keys; key_script; _ } : Options.t) =
  match key_script with
  | None -> Key_script.constant keys |> Ok
  | Some filename -> Key_script.load filename ~initial:keys
;;

(* Step until the run ends, printing the trace lines if asked: how it ended, and the steps. *)
let run_to_end ({ max_steps; trace; _ } : Options.t) ~key_script =
  let rec go run =
    match Run.status run with
    | Some status -> status, Run.retired run
    | None ->
      let retired = Run.retired run in
      let keys = Key_script.at key_script ~retired in
      let run = Run.step run ~keys in
      (match trace with
       | Print_steps -> Machine.trace () |> print_line
       | No_trace -> ());
      go run
  in
  Run.create ~max_steps |> go
;;

let run (options : Options.t) =
  Machine.start ();
  let%bind.Or_error () = Image.load options.image in
  let%map.Or_error key_script = load_key_script options in
  let status, steps = run_to_end options ~key_script in
  print_line [%string "status %{status#Run.Status}"];
  print_line [%string "steps %{steps#Int}"];
  Machine.dump () |> Out_channel.output_string stdout;
  (match options.framebuffer with
   | Print_framebuffer -> print_framebuffer ()
   | No_framebuffer -> ());
  Run.Status.exit_code status
;;
