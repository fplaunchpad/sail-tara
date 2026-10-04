open Core
open Libsail
open Type_check
open Extraction.Ast

module Function_clause = struct
  type t =
    { name : string
    ; pattern : tannot pat
    ; guarded : bool
    ; body : tannot exp
    ; documented : bool
    ; location : Parse_ast.l
    }
end

module Mapping_clause = struct
  type t =
    { name : string
    ; left : tannot mpat
    ; right : tannot mpat
    ; documented : bool
    ; location : Parse_ast.l
    }
end

module Anchor = struct
  type t =
    { name : string
    ; location : Parse_ast.l
    }
end

let id_string = Ast_util.string_of_id
let fail_at location message = raise (Reporting.err_general location message)
let pat_location (P_aux (_, (location, _))) = location
let mpat_location (MP_aux (_, (location, _))) = location
let exp_location (E_aux (_, (location, _))) = location

let rec start = function
  | Parse_ast.Range (position, _) -> Some position
  | Parse_ast.Unique (_, location) | Parse_ast.Generated location -> start location
  | Parse_ast.Hint (_, location, _) -> start location
  | Parse_ast.Unknown -> None
;;

let file_of (position : Sail_file.position) =
  Sail_file.to_path position.pos_fname |> Sail_file.Path.to_string
;;

let source_file location =
  match start location with
  | Some position -> file_of position
  | None -> fail_at location "a definition has no source location"
;;

let rec unwrap_pat (P_aux (aux, _) as pattern : tannot pat) =
  match aux with
  | P_typ (_, nested) | P_var (nested, _) -> unwrap_pat nested
  | _ -> pattern
;;

let rec unwrap_mpat (MP_aux (aux, _) as pattern : tannot mpat) =
  match aux with
  | MP_typ (nested, _) | MP_as (nested, _) -> unwrap_mpat nested
  | _ -> pattern
;;

let is_unit_mpat pattern =
  match unwrap_mpat pattern with
  | MP_aux (MP_lit (L_aux (L_unit, _)), _) -> true
  | _ -> false
;;

let constructor_pat pattern =
  match unwrap_pat pattern with
  | P_aux (P_app (id, _), _) -> Some (id_string id)
  | _ -> None
;;

let constructor_mpat pattern =
  match unwrap_mpat pattern with
  | MP_aux (MP_app (id, [ argument ]), _) when is_unit_mpat argument -> Some (id_string id, [])
  | MP_aux (MP_app (id, [ MP_aux (MP_tuple arguments, _) ]), _) -> Some (id_string id, arguments)
  | MP_aux (MP_app (id, arguments), _) -> Some (id_string id, arguments)
  | _ -> None
;;

let expression_arguments = function
  | [ E_aux (E_lit (L_aux (L_unit, _)), _) ] -> []
  | [ E_aux (E_tuple arguments, _) ] -> arguments
  | arguments -> arguments
;;

let decode_result body =
  match body with
  | E_aux (E_app (some, [ E_aux (E_app (constructor, arguments), _) ]), _)
    when String.equal (id_string some) "Some" ->
    Some (id_string constructor, expression_arguments arguments)
  | E_aux (E_app (none, _), _) when String.equal (id_string none) "None" -> None
  | body -> fail_at (exp_location body) "a decode clause must return Some(instruction) or None()"
;;

let literal_bits location (L_aux (literal, _) as full_literal : lit) =
  match literal with
  | L_bin _ -> String.drop_prefix (Ast_util.string_of_lit full_literal) 2
  | L_hex _ -> String.drop_prefix (Ast_util.string_of_lit full_literal) 2 |> Ast_util.hex_to_bin
  | _ -> fail_at location "expected a binary or hexadecimal literal"
;;

let width_of_pat env pattern =
  let pattern = unwrap_pat pattern in
  match
    Type_check.typ_of_pat pattern
    |> Type_check.destruct_bitvector env
    |> Option.bind ~f:Type_check.big_int_of_nexp
  with
  | Some width -> Big_int.to_int width
  | None -> fail_at (pat_location pattern) "a decode field must have a fixed width"
;;

let function_clauses (ast : Type_check.typed_ast) =
  List.concat_map ast.defs ~f:(function
    | DEF_aux (DEF_fundef (FD_aux (FD_function (_, _, clauses), _)), _) ->
      List.map clauses ~f:(fun (FCL_aux (FCL_funcl (id, Pat_aux (clause, _)), (annot, _))) ->
        let pattern, guarded, body =
          match clause with
          | Pat_exp (pattern, body) -> pattern, false, body
          | Pat_when (pattern, _, body) -> pattern, true, body
        in
        ({ name = id_string id
         ; pattern
         ; guarded
         ; body
         ; documented = Option.is_some annot.doc_comment
         ; location = annot.loc
         }
         : Function_clause.t))
    | _ -> [])
;;

let mapping_clauses (ast : Type_check.typed_ast) =
  List.concat_map ast.defs ~f:(function
    | DEF_aux (DEF_mapdef (MD_aux (MD_mapping (id, _, clauses), _)), _) ->
      List.filter_map clauses ~f:(fun (MCL_aux (clause, (annot, _))) ->
        match clause with
        | MCL_bidir (MPat_aux (MPat_pat left, _), MPat_aux (MPat_pat right, _)) ->
          Some
            ({ name = id_string id
             ; left
             ; right
             ; documented = Option.is_some annot.doc_comment
             ; location = annot.loc
             }
             : Mapping_clause.t)
        | _ -> None)
    | _ -> [])
;;

let anchors (ast : Type_check.typed_ast) =
  List.filter_map ast.defs ~f:(function
    | DEF_aux (DEF_pragma ("anchor", Pragma_line (name, _)), annot)
      when Option.is_some annot.doc_comment ->
      Some ({ name = String.strip name; location = annot.loc } : Anchor.t)
    | _ -> None)
;;

let order (ast : Type_check.typed_ast) =
  (* Include directives become pragmas located in the including file, so pragmas do not count. *)
  let locations =
    List.concat_map ast.defs ~f:(fun (DEF_aux (def, annot)) ->
      let nested =
        match def with
        | DEF_type (TD_aux (TD_variant (_, _, constructors, _), _)) ->
          List.map constructors ~f:(fun (Tu_aux (_, annot)) -> annot.loc)
        | DEF_fundef (FD_aux (FD_function (_, _, clauses), _)) ->
          List.map clauses ~f:(fun (FCL_aux (_, (annot, _))) -> annot.loc)
        | DEF_mapdef (MD_aux (MD_mapping (_, _, clauses), _)) ->
          List.map clauses ~f:(fun (MCL_aux (_, (annot, _))) -> annot.loc)
        | _ -> []
      in
      match def with
      | DEF_pragma _ -> []
      | _ -> annot.loc :: nested)
  in
  let files =
    List.filter_map locations ~f:(fun location -> start location |> Option.map ~f:file_of)
    |> List.fold ~init:[] ~f:(fun files file ->
      if List.mem files file ~equal:String.equal then files else file :: files)
    |> List.rev
  in
  fun location ->
    match start location with
    | Some position ->
      ( List.findi files ~f:(fun _ file -> String.equal file (file_of position))
        |> Option.value_map ~default:Int.max_value ~f:fst
      , position.pos_cnum )
    | None -> Int.max_value, 0
;;
