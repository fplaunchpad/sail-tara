open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Selector = struct
  type t =
    | Pattern
    | Body
    | Left
    | Right

  let yojson_of_t selector =
    `String
      (match selector with
       | Pattern -> "pattern"
       | Body -> "body"
       | Left -> "left"
       | Right -> "right")
  ;;
end

type t =
  { name : string [@key "function"]
  ; selector : Selector.t
  ; documented : bool
  }
[@@deriving yojson_of]

(* The constructor a clause body builds, as a decode clause does. *)
let built = function
  | E_aux (E_app (some, [ E_aux (E_app (constructor, _), _) ]), _)
    when String.equal (Sail_ast.id_string some) "Some" -> Some (Sail_ast.id_string constructor)
  | E_aux (E_app (constructor, _), _) -> Some (Sail_ast.id_string constructor)
  | _ -> None
;;

let read ~ast ~constructors =
  let instruction = Option.filter ~f:(Set.mem constructors) in
  let from_functions =
    List.filter_map
      (Sail_ast.function_clauses ast)
      ~f:(fun { name; pattern; body; documented; location; _ } ->
        let clause selector = { name; selector; documented } in
        match instruction (Sail_ast.constructor_pat pattern), instruction (built body) with
        | Some constructor, _ -> Some (constructor, location, clause Pattern)
        | None, Some constructor -> Some (constructor, location, clause Body)
        | None, None -> None)
  in
  let from_mappings =
    List.filter_map
      (Sail_ast.mapping_clauses ast)
      ~f:(fun { name; left; right; documented; location } ->
        let constructor side = instruction (Option.map (Sail_ast.constructor_mpat side) ~f:fst) in
        let clause selector = { name; selector; documented } in
        match constructor left, constructor right with
        | Some constructor, _ -> Some (constructor, location, clause Left)
        | None, Some constructor -> Some (constructor, location, clause Right)
        | None, None -> None)
  in
  let order = Sail_ast.order ast in
  from_functions @ from_mappings
  |> List.sort ~compare:(fun (_, left, _) (_, right, _) ->
    [%compare: int * int] (order left) (order right))
  |> List.map ~f:(fun (constructor, _, clause) -> constructor, clause)
  |> String.Map.of_alist_multi
;;
