open! Import

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
  ; retired : int
  ; last : Machine.Step.t option
  }

let create ~max_steps = ({ max_steps; retired = 0; last = None } : t)
let retired t = t.retired

let status t : Status.t option =
  match t.last, Machine.cpu () with
  | Some Illegal, _ -> Some Illegal
  | (Some (Retired | Stopped) | None), Halted -> Some Halted
  | (Some (Retired | Stopped) | None), Running ->
    if t.max_steps > 0 && t.retired = t.max_steps then Some Limit else None
;;

let step t ~keys =
  let step = Machine.step ~keys:(Keys.to_int keys) in
  match step with
  | Retired -> { t with retired = t.retired + 1; last = Some step }
  | Stopped | Illegal -> { t with last = Some step }
;;
