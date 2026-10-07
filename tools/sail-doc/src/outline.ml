open Core
open Libsail
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Item = struct
  module Anchor = struct
    type t = { name : string } [@@deriving yojson_of]
  end

  module Constructor = struct
    type t =
      { name : string
      ; clauses : Clause.t list
      }
    [@@deriving yojson_of]
  end

  type t =
    | Anchor of string
    | Constructor of Constructor.t

  let yojson_of_t = function
    | Anchor name -> Tagged.json ~kind:"anchor" (Anchor.yojson_of_t { name })
    | Constructor constructor ->
      Tagged.json ~kind:"constructor" (Constructor.yojson_of_t constructor)
  ;;
end

type t = Item.t list [@@deriving yojson_of]

let read ~ast ~(constructors : (Item.Constructor.t * Parse_ast.l) list) =
  let files =
    List.map constructors ~f:(fun (_, location) -> Sail_ast.source_file location)
    |> String.Set.of_list
  in
  let anchors =
    List.filter_map (Prose.anchors ast) ~f:(fun (({ name; _ } : Prose.Fragment.t), location) ->
      Option.some_if (Set.mem files (Sail_ast.source_file location)) (Item.Anchor name, location))
  in
  let constructors =
    List.map constructors ~f:(fun (constructor, location) -> Item.Constructor constructor, location)
  in
  let order = Sail_ast.order ast in
  anchors @ constructors
  |> List.stable_sort ~compare:(fun (_, left) (_, right) ->
    [%compare: int * int] (order left) (order right))
  |> List.map ~f:fst
;;
