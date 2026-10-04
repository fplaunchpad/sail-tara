open Core
open Libsail
open Type_check
open Extraction.Ast

module Function_clause = struct
  type t =
    { name : string
    ; pattern : tannot pat
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
    ; guard : tannot exp option
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
let mpat_location (MP_aux (_, (location, _))) = location
let exp_location (E_aux (_, (location, _))) = location

let rec range = function
  | Parse_ast.Range (start, finish) -> Some (start, finish)
  | Parse_ast.Unique (_, location) | Parse_ast.Generated location -> range location
  | Parse_ast.Hint (_, location, _) -> range location
  | Parse_ast.Unknown -> None
;;

let file_of (position : Sail_file.position) =
  Sail_file.to_path position.pos_fname |> Sail_file.Path.to_string
;;

let source_file location =
  match range location with
  | Some (start, _) -> file_of start
  | None -> fail_at location "a definition has no source location"
;;

let source_span first last =
  match range first, range last with
  | Some ((start : Sail_file.position), _), Some (_, (finish : Sail_file.position)) ->
    String.sub
      (Sail_file.contents start.pos_fname)
      ~pos:start.pos_cnum
      ~len:(finish.pos_cnum - start.pos_cnum)
  | _ -> fail_at first "a definition has no source location"
;;

let source_text location = source_span location location

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

module Argument = struct
  type t =
    | Binder of string
    | Constant of string
    | Wildcard
    | Other
  [@@deriving equal]

  let of_id env id =
    if Type_check.is_enum_member id env then Constant (id_string id) else Binder (id_string id)
  ;;

  let of_pat env pattern =
    match unwrap_pat pattern with
    | P_aux (P_id id, _) -> of_id env id
    | P_aux (P_lit literal, _) -> Constant (Ast_util.string_of_lit literal)
    | P_aux (P_wild, _) -> Wildcard
    | _ -> Other
  ;;

  let of_mpat env pattern =
    match unwrap_mpat pattern with
    | MP_aux (MP_id id, _) -> of_id env id
    | MP_aux (MP_lit literal, _) -> Constant (Ast_util.string_of_lit literal)
    | _ -> Other
  ;;
end

let constructor_pat pattern =
  match unwrap_pat pattern with
  | P_aux (P_app (id, [ argument ]), _) ->
    (match unwrap_pat argument with
     | P_aux (P_lit (L_aux (L_unit, _)), _) -> Some (id_string id, [])
     | P_aux (P_tuple arguments, _) -> Some (id_string id, arguments)
     | _ -> Some (id_string id, [ argument ]))
  | P_aux (P_app (id, arguments), _) -> Some (id_string id, arguments)
  | _ -> None
;;

let constructor_mpat pattern =
  match unwrap_mpat pattern with
  | MP_aux (MP_app (id, [ argument ]), _) ->
    (match unwrap_mpat argument with
     | MP_aux (MP_lit (L_aux (L_unit, _)), _) -> Some (id_string id, [])
     | MP_aux (MP_tuple arguments, _) -> Some (id_string id, arguments)
     | _ -> Some (id_string id, [ argument ]))
  | MP_aux (MP_app (id, arguments), _) -> Some (id_string id, arguments)
  | _ -> None
;;

let literal_bits location (L_aux (literal, _) as full_literal : lit) =
  match literal with
  | L_bin _ -> String.drop_prefix (Ast_util.string_of_lit full_literal) 2
  | L_hex _ -> String.drop_prefix (Ast_util.string_of_lit full_literal) 2 |> Ast_util.hex_to_bin
  | _ -> fail_at location "expected a binary or hexadecimal literal"
;;

let bits_width env typ =
  let%bind.Option width =
    Type_check.Env.expand_synonyms env typ |> Type_check.destruct_bitvector env
  in
  let%map.Option width = Type_check.big_int_of_nexp width in
  Big_int.to_int width
;;

let width_of_mpat env pattern =
  match Type_check.typ_of_mpat pattern |> bits_width env with
  | Some width -> width
  | None -> fail_at (mpat_location pattern) "an encoding field must have a fixed width"
;;

let function_clauses (ast : typed_ast) =
  List.concat_map ast.defs ~f:(function
    | DEF_aux (DEF_fundef (FD_aux (FD_function (_, _, clauses), _)), _) ->
      List.map clauses ~f:(fun (FCL_aux (FCL_funcl (id, Pat_aux (clause, _)), (annot, _))) ->
        let pattern, body =
          match clause with
          | Pat_exp (pattern, body) | Pat_when (pattern, _, body) -> pattern, body
        in
        ({ name = id_string id
         ; pattern
         ; body
         ; documented = Option.is_some annot.doc_comment
         ; location = annot.loc
         }
         : Function_clause.t))
    | _ -> [])
;;

let mapping_clauses (ast : typed_ast) =
  let side (MPat_aux (side, _)) =
    match side with
    | MPat_pat pattern -> pattern, None
    | MPat_when (pattern, guard) -> pattern, Some guard
  in
  List.concat_map ast.defs ~f:(function
    | DEF_aux (DEF_mapdef (MD_aux (MD_mapping (id, _, clauses), _)), _) ->
      List.filter_map clauses ~f:(fun (MCL_aux (clause, (annot, _))) ->
        match clause with
        | MCL_bidir (left, right) ->
          let left, left_guard = side left in
          let right, right_guard = side right in
          Some
            ({ name = id_string id
             ; left
             ; right
             ; guard = Option.first_some left_guard right_guard
             ; documented = Option.is_some annot.doc_comment
             ; location = annot.loc
             }
             : Mapping_clause.t)
        | MCL_forwards _ | MCL_backwards _ -> None)
    | _ -> [])
;;

let anchors (ast : typed_ast) =
  List.filter_map ast.defs ~f:(function
    | DEF_aux (DEF_pragma ("anchor", Pragma_line (name, _)), annot)
      when Option.is_some annot.doc_comment ->
      Some ({ name = String.strip name; location = annot.loc } : Anchor.t)
    | _ -> None)
;;

let order (ast : typed_ast) =
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
    List.filter_map locations ~f:(fun location ->
      let%map.Option start, _ = range location in
      file_of start)
    |> List.fold ~init:[] ~f:(fun files file ->
      if List.mem files file ~equal:String.equal then files else file :: files)
    |> List.rev
  in
  fun location ->
    match range location with
    | Some ((start : Sail_file.position), _) ->
      ( List.findi files ~f:(fun _ file -> String.equal file (file_of start))
        |> Option.value_map ~default:Int.max_value ~f:fst
      , start.pos_cnum )
    | None -> Int.max_value, 0
;;
