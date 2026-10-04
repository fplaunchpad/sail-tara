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

type t =
  { max_steps : int
  ; mutable retired : int
  ; mutable illegal : bool
  }

let create ~max_steps = { max_steps; retired = 0; illegal = false }
let retired t = t.retired

let status t : Status.t option =
  if t.illegal
  then Some Illegal
  else if Machine.halted ()
  then Some Halted
  else if t.max_steps > 0 && t.retired = t.max_steps
  then Some Limit
  else None
;;

let step t ~keys =
  match Machine.step ~keys:(Keys.to_int keys) with
  | Retired -> t.retired <- t.retired + 1
  | Illegal -> t.illegal <- true
  | Stopped -> ()
;;
