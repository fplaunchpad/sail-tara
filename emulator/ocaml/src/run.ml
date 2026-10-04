open! Core

module Status = struct
  type t =
    | Halted
    | Limit
    | Illegal
  [@@deriving string ~capitalize:"snake_case"]

  let exit_code = function
    | Halted -> 0
    | Limit -> 3
    | Illegal -> 4
  ;;
end

let run ~max_steps ~trace =
  let trace_line () = if trace then print_endline (Machine.trace ()) in
  let rec go steps : Status.t * int =
    if Machine.halted ()
    then Halted, steps
    else if max_steps > 0 && steps = max_steps
    then Limit, steps
    else (
      match Machine.step ~keys:0 with
      | Stopped -> Halted, steps
      | Retired ->
        trace_line ();
        go (steps + 1)
      | Illegal ->
        trace_line ();
        Illegal, steps)
  in
  go 0
;;
