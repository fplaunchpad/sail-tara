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

let constructor_pat pattern =
  match unwrap_pat pattern with
  | P_aux (P_app (id, arguments), _) -> Some (id_string id, arguments)
  | _ -> None
;;

let constructor_mpat pattern =
  match unwrap_mpat pattern with
  | MP_aux (MP_app (id, arguments), _) -> Some (id_string id, arguments)
  | _ -> None
;;

let pattern_args = function
  | [ P_aux (P_lit (L_aux (L_unit, _)), _) ] -> []
  | [ P_aux (P_tuple arguments, _) ] -> arguments
  | arguments -> arguments
;;

let expression_args = function
  | [ E_aux (E_lit (L_aux (L_unit, _)), _) ] -> []
  | [ E_aux (E_tuple arguments, _) ] -> arguments
  | arguments -> arguments
;;

let expression_id = function
  | E_aux (E_id id, _) -> Some (id_string id)
  | _ -> None
;;

let decode_result body =
  match body with
  | E_aux (E_app (some, [ E_aux (E_app (constructor, arguments), _) ]), _)
    when String.equal (id_string some) "Some" ->
    let names =
      List.map (expression_args arguments) ~f:(fun expression ->
        match expression_id expression with
        | Some name -> name
        | None ->
          fail_at
            (match expression with
             | E_aux (_, (location, _)) -> location)
            "decode constructor arguments must be direct pattern identifiers")
    in
    Some (id_string constructor, names)
  | E_aux (E_app (none, _), _) when String.equal (id_string none) "None" -> None
  | E_aux (_, (location, _)) ->
    fail_at location "decode clause must construct Some(instruction) or None()"
;;

let literal_bits location (L_aux (literal, _) as full_literal : lit) =
  match literal with
  | L_bin _ -> String.drop_prefix (Ast_util.string_of_lit full_literal) 2
  | L_hex _ -> String.drop_prefix (Ast_util.string_of_lit full_literal) 2 |> Ast_util.hex_to_bin
  | _ -> fail_at location "expected a binary or hexadecimal bit-vector literal"
;;

let positive_width location width =
  match width with
  | Some width when width > 0 -> width
  | _ -> fail_at location "expected a statically known positive bit-vector width"
;;

let width_of_pat env pattern =
  let pattern = unwrap_pat pattern in
  Type_check.typ_of_pat pattern
  |> Type_check.destruct_bitvector env
  |> Option.bind ~f:Type_check.big_int_of_nexp
  |> Option.map ~f:Big_int.to_int
  |> positive_width (pat_location pattern)
;;

let width_of_exp env expression =
  Type_check.typ_of expression
  |> Type_check.destruct_bitvector env
  |> Option.bind ~f:Type_check.big_int_of_nexp
  |> Option.map ~f:Big_int.to_int
  |> positive_width
       (match expression with
        | E_aux (_, (location, _)) -> location)
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
          fail_at annot.loc [%string "unsupported %{name} mapping clause"])
    | _ -> [])
;;
