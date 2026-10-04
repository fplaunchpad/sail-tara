open Core
open Libsail

module Item = struct
  type t =
    | Anchor of string
    | Instruction of string

  let yojson_of_t item =
    let kind, name =
      match item with
      | Anchor name -> "anchor", name
      | Instruction name -> "instruction", name
    in
    `Assoc [ "kind", `String kind; "name", `String name ]
  ;;
end

type t = Item.t list

let yojson_of_t items = `List (List.map items ~f:Item.yojson_of_t)

let read ~ast ~(constructors : (string * Parse_ast.l) list) =
  let files =
    List.map constructors ~f:(fun (_, location) -> Sail_ast.source_file location)
    |> String.Set.of_list
  in
  let anchors =
    List.filter_map (Sail_ast.anchors ast) ~f:(fun { name; location } ->
      Option.some_if (Set.mem files (Sail_ast.source_file location)) (Item.Anchor name, location))
  in
  let instructions =
    List.map constructors ~f:(fun (name, location) -> Item.Instruction name, location)
  in
  let order = Sail_ast.order ast in
  anchors @ instructions
  |> List.sort ~compare:(fun (_, left) (_, right) ->
    [%compare: int * int] (order left) (order right))
  |> List.map ~f:fst
;;
