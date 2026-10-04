open Core
open Libsail
open Type_check
open Extraction.Ast

module Function_clause = struct
  type t =
    { pattern : tannot pat
    ; body : tannot exp
    }
end

module Mapping_clause = struct
  type t =
    { left : tannot mpat
    ; right : tannot mpat
    ; location : Parse_ast.l
    }
end

let id_string = Ast_util.string_of_id
let fail_at location message = raise (Reporting.err_general location message)
let pat_location (P_aux (_, (location, _))) = location
let mpat_location (MP_aux (_, (location, _))) = location
let exp_location (E_aux (_, (location, _))) = location

let rec source_file = function
  | Parse_ast.Range (position, _) ->
    Sail_file.to_path position.pos_fname |> Sail_file.Path.to_string
  | Parse_ast.Unique (_, location) | Parse_ast.Generated location -> source_file location
  | Parse_ast.Hint (_, location, _) -> source_file location
  | Parse_ast.Unknown -> fail_at Parse_ast.Unknown "a definition has no source location"
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
    let operands =
      List.map (expression_arguments arguments) ~f:(function
        | E_aux (E_id id, _) -> id_string id
        | argument ->
          fail_at (exp_location argument) "a decoded instruction's operands must be field names")
    in
    Some (id_string constructor, operands)
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

let function_clauses (ast : Type_check.typed_ast) name : Function_clause.t list =
  List.concat_map ast.defs ~f:(function
    | DEF_aux (DEF_fundef (FD_aux (FD_function (_, _, clauses), _)), _) ->
      List.filter_map clauses ~f:(function
        | FCL_aux (FCL_funcl (id, Pat_aux (Pat_exp (pattern, body), _)), _)
          when String.equal (id_string id) name -> Some ({ pattern; body } : Function_clause.t)
        | FCL_aux (FCL_funcl (id, Pat_aux (Pat_when (pattern, _, _), _)), _)
          when String.equal (id_string id) name ->
          fail_at (pat_location pattern) [%string "guarded %{name} clauses are not supported"]
        | _ -> None)
    | _ -> [])
;;

let mapping_clauses (ast : Type_check.typed_ast) name : Mapping_clause.t list =
  List.concat_map ast.defs ~f:(function
    | DEF_aux (DEF_mapdef (MD_aux (MD_mapping (id, _, clauses), _)), _)
      when String.equal (id_string id) name ->
      List.filter_map clauses ~f:(function
        | MCL_aux (MCL_bidir (MPat_aux (MPat_pat left, _), MPat_aux (MPat_pat right, _)), (annot, _))
          -> Some ({ left; right; location = annot.loc } : Mapping_clause.t)
        | MCL_aux (_, (annot, _)) ->
          fail_at annot.loc [%string "%{name} must be made of unguarded two-way clauses"])
    | _ -> [])
;;
