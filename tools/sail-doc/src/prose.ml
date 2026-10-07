open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Fragment = struct
  type t =
    { name : string
    ; description : string
    }
  [@@deriving yojson_of]
end

type t =
  { anchors : Fragment.t list
  ; registers : Fragment.t list
  ; constants : Fragment.t list
  }
[@@deriving yojson_of]

let annotations (ast : Type_check.typed_ast) =
  List.concat_map ast.defs ~f:(fun (DEF_aux (definition, annot)) ->
    let nested =
      match definition with
      | DEF_type (TD_aux (TD_variant (_, _, constructors, _), _)) ->
        List.map constructors ~f:(fun (Tu_aux (_, annot)) -> { annot with env = () })
      | DEF_fundef (FD_aux (FD_function (_, _, clauses), _)) ->
        List.filter_map clauses ~f:(fun (FCL_aux (_, (clause, _))) ->
          Option.some_if (Option.is_none annot.doc_comment) clause)
      | DEF_mapdef (MD_aux (MD_mapping (_, _, clauses), _)) ->
        List.filter_map clauses ~f:(fun (MCL_aux (_, (clause, _))) ->
          Option.some_if (Option.is_none annot.doc_comment) clause)
      | _ -> []
    in
    { annot with env = () } :: nested)
;;

let anchors ast =
  let anchors =
    List.concat_map (annotations ast) ~f:(fun annot ->
      Option.value_map (Doc_comment.read annot) ~default:[] ~f:(fun doc ->
        List.map doc.anchors ~f:(fun { name; text } ->
          ({ name; description = text } : Fragment.t), annot.loc)))
  in
  List.fold anchors ~init:String.Set.empty ~f:(fun found ((fragment : Fragment.t), location) ->
    if Set.mem found fragment.name
    then Sail_ast.fail_at location [%string "duplicate @anchor %{fragment.name}"];
    Set.add found fragment.name)
  |> (ignore : String.Set.t -> unit);
  anchors
;;

let read (ast : Type_check.typed_ast) =
  let fragments select =
    List.filter_map ast.defs ~f:(fun (DEF_aux (definition, annot)) ->
      let%bind.Option name = select definition in
      let%bind.Option _ = annot.doc_comment in
      let description = Doc_comment.body annot in
      Some ({ name; description } : Fragment.t))
  in
  { anchors = List.map (anchors ast) ~f:fst
  ; registers =
      fragments (function
        | DEF_register (DEC_aux (DEC_reg (_, id, _), _)) -> Some (Sail_ast.id_string id)
        | _ -> None)
  ; constants =
      fragments (function
        | DEF_let (pattern, _) ->
          (match Sail_ast.unwrap_pat pattern with
           | P_aux (P_id id, _) -> Some (Sail_ast.id_string id)
           | _ -> None)
        | _ -> None)
  }
;;
