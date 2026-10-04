open! Core

module Line = struct
  type t =
    | Up
    | Down
    | Left
    | Right
    | Quit
  [@@deriving enumerate, equal, string ~capitalize:"snake_case"]

  let index line = List.findi_exn all ~f:(fun _ other -> equal line other) |> fst
  let letter line = (to_string line).[0] |> Char.uppercase
end

type t = int [@@deriving equal]

let none = 0
let bit line = 1 lsl Line.index line
let of_lines lines = List.fold lines ~init:none ~f:(fun keys line -> keys lor bit line)
let mem keys line = keys land bit line <> 0
let to_int keys = keys
let all = of_lines Line.all

let of_string text =
  let%bind.Or_error keys = Number.decimal_or_hex text in
  if keys <= all
  then Ok keys
  else Or_error.error_s [%message [%string "expected input lines 0 to %{all#Int}"] text]
;;
