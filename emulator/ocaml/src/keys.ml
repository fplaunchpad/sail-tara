open! Import

module Line = struct
  module T = struct
    type t =
      | Up
      | Down
      | Left
      | Right
      | Quit
    [@@deriving enumerate, compare, sexp_of, string ~capitalize:"snake_case", variants]
  end

  include T
  include Comparable.Make_plain (T)

  let letter line =
    let name = to_string line in
    name.[0] |> Char.uppercase
  ;;

  let of_key : char -> t option = function
    | 'w' | 'W' -> Some Up
    | 's' | 'S' -> Some Down
    | 'a' | 'A' -> Some Left
    | 'd' | 'D' -> Some Right
    | 'q' | 'Q' -> Some Quit
    | _ -> None
  ;;

  let of_arrow : char -> t option = function
    | 'A' -> Some Up
    | 'B' -> Some Down
    | 'C' -> Some Right
    | 'D' -> Some Left
    | _ -> None
  ;;
end

module State = struct
  type t =
    | Held
    | Released
end

type t = int [@@deriving equal]

let none = 0
let bit line = 1 lsl Line.Variants.to_rank line
let of_lines lines = List.fold lines ~init:none ~f:(fun keys line -> keys lor bit line)
let state keys line = if keys land bit line <> 0 then State.Held else Released
let to_int keys = keys
let every_line = of_lines Line.all

let of_string text =
  let%bind.Or_error keys = Number.decimal_or_hex text in
  if keys <= every_line
  then Ok keys
  else Or_error.error_s [%message [%string "expected input lines 0 to %{every_line#Int}"] text]
;;
