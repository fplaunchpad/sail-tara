open! Import

let default_max_steps = 1_000_000
let default_hz = 2000
let arg_type of_string = Command.Arg_type.create (fun text -> of_string text |> Or_error.ok_exn)
let count = arg_type Number.decimal
let keys = arg_type Keys.of_string

let run =
  let%map_open.Command trace =
    flag
      "--trace"
      ~aliases:[ "-t" ]
      (no_arg_some Batch.Trace.Print_steps)
      ~doc:" print a trace line for each step"
  and max_steps =
    flag
      "--max-steps"
      ~aliases:[ "-n" ]
      (optional_with_default default_max_steps count)
      ~doc:"N stop after N retirements (default 1000000; 0: no limit)"
  and keys =
    flag
      "--keys"
      (optional_with_default Keys.none keys)
      ~doc:"K input lines, 0-31 in decimal or 0x hex (default 0)"
  and key_script =
    flag
      "--key-script"
      (optional Filename_unix.arg_type)
      ~doc:"FILE change the input lines as it says: lines of STEP KEYS"
  and framebuffer =
    flag
      "--framebuffer"
      (no_arg_some Batch.Framebuffer_dump.Print_framebuffer)
      ~doc:" print the framebuffer after the dump"
  and image = anon ("IMAGE" %: Filename_unix.arg_type) in
  ({ image
   ; max_steps
   ; trace = Option.value trace ~default:Batch.Trace.No_trace
   ; keys
   ; key_script
   ; framebuffer = Option.value framebuffer ~default:Batch.Framebuffer_dump.No_framebuffer
   }
   : Batch.Options.t)
;;

let play =
  let%map_open.Command max_steps =
    flag
      "--max-steps"
      ~aliases:[ "-n" ]
      (optional_with_default 0 count)
      ~doc:"N stop after N retirements (default: no limit; 0: no limit)"
  and hz =
    flag
      "--hz"
      (optional_with_default default_hz count)
      ~doc:"N instructions per second (default 2000; 0: as fast as possible)"
  and image = anon ("IMAGE" %: Filename_unix.arg_type) in
  ({ image; max_steps; hz } : Interactive.Options.t)
;;
