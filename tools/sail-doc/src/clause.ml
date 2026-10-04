open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Selector = struct
  type t =
    | Pattern
    | Left
    | Right
  [@@deriving equal]

  let yojson_of_t selector =
    `String
      (match selector with
       | Pattern -> "pattern"
       | Left -> "left"
       | Right -> "right")
  ;;
end

type t =
  { name : string [@key "function"]
  ; selector : Selector.t
  ; pattern : string
  ; documented : bool
  }
[@@deriving yojson_of]

(* The Sail Asciidoctor plugin matches an enum member, or a binary or hexadecimal literal, by its
   spelling, and anything else only with a wildcard (None). *)
let of_id env id = Option.some_if (Type_check.is_enum_member id env) (Sail_ast.id_string id)

let of_literal (L_aux (literal, _) as full_literal) =
  match literal with
  | L_bin _ | L_hex _ -> Some (Ast_util.string_of_lit full_literal)
  | _ -> None
;;

let of_pat env pattern =
  match Sail_ast.unwrap_pat pattern with
  | P_aux (P_id id, _) -> of_id env id
  | P_aux (P_lit literal, _) -> of_literal literal
  | _ -> None
;;

let of_mpat env pattern =
  match Sail_ast.unwrap_mpat pattern with
  | MP_aux (MP_id id, _) -> of_id env id
  | MP_aux (MP_lit literal, _) -> of_literal literal
  | _ -> None
;;

module Found = struct
  (* A clause, with its constructor, location and the constants the plugin matches it by. *)
  type nonrec t =
    { constructor : string
    ; location : Parse_ast.l
    ; constants : string option list
    ; clause : t
    }

  let make ~constructor ~location ~constants ~name ~selector ~documented =
    let arguments = List.map constants ~f:(Option.value ~default:"_") |> String.concat ~sep:", " in
    { constructor
    ; location
    ; constants
    ; clause = { name; selector; pattern = [%string "%{constructor}(%{arguments})"]; documented }
    }
  ;;

  (* Whether the plugin, looking for [found], would stop at [earlier] first. *)
  let hides ~earlier found =
    String.equal earlier.clause.name found.clause.name
    && Selector.equal earlier.clause.selector found.clause.selector
    && String.equal earlier.constructor found.constructor
    &&
    match List.zip found.constants earlier.constants with
    | Ok pairs ->
      List.for_all pairs ~f:(fun (constant, other) ->
        Option.is_none constant || [%equal: string option] constant other)
    | Unequal_lengths -> true
  ;;
end

let read ~ast ~env ~constructors =
  let instruction application =
    let%bind.Option constructor, arguments = application in
    Option.some_if (Set.mem constructors constructor) (constructor, arguments)
  in
  let from_functions =
    List.filter_map
      (Sail_ast.function_clauses ast)
      ~f:(fun { name; pattern; documented; location; _ } ->
        let%map.Option constructor, arguments = instruction (Sail_ast.constructor_pat pattern) in
        Found.make
          ~constructor
          ~location
          ~constants:(List.map arguments ~f:(of_pat env))
          ~name
          ~selector:Pattern
          ~documented)
  in
  let from_mappings =
    List.filter_map
      (Sail_ast.mapping_clauses ast)
      ~f:(fun { name; left; right; documented; location; _ } ->
        let side (selector : Selector.t) pattern =
          let%map.Option constructor, arguments = instruction (Sail_ast.constructor_mpat pattern) in
          Found.make
            ~constructor
            ~location
            ~constants:(List.map arguments ~f:(of_mpat env))
            ~name
            ~selector
            ~documented
        in
        Option.first_some (side Left left) (side Right right))
  in
  let order = Sail_ast.order ast in
  let found =
    from_functions @ from_mappings
    |> List.sort ~compare:(fun (left : Found.t) right ->
      [%compare: int * int] (order left.location) (order right.location))
  in
  List.iteri found ~f:(fun index (clause : Found.t) ->
    if List.exists (List.take found index) ~f:(fun earlier -> Found.hides ~earlier clause)
    then
      Sail_ast.fail_at
        clause.location
        [%string
          "an earlier clause of %{clause.clause.name} also matches %{clause.clause.pattern}, so \
           the specification cannot show this one"]);
  List.map found ~f:(fun { constructor; clause; _ } -> constructor, clause)
  |> String.Map.of_alist_multi
;;
