open Core
open Libsail
open Extraction.Ast

type t = string String.Map.t

(* Sail's library, written as a reference card writes it. *)
let library = [ "bitzero", "0"; "bitone", "1" ]

let read (ast : Type_check.typed_ast) =
  let named =
    List.filter_map ast.defs ~f:(fun (DEF_aux (def, annot)) ->
      let%bind.Option name =
        match def with
        | DEF_fundef (FD_aux (FD_function (_, _, FCL_aux (FCL_funcl (id, _), _) :: _), _))
        | DEF_val (VS_aux (VS_val_spec (_, id, _), _))
        | DEF_register (DEC_aux (DEC_reg (_, id, _), _)) -> Some (Sail_ast.id_string id)
        | DEF_let (pattern, _) ->
          (match Sail_ast.unwrap_pat pattern with
           | P_aux (P_id id, _) -> Some (Sail_ast.id_string id)
           | _ -> None)
        | _ -> None
      in
      match Ast_util.get_def_attribute "notation" annot with
      | Some (_, Some (AD_aux (AD_string template, _))) -> Some (name, template)
      | Some (location, _) ->
        Sail_ast.fail_at location "a notation is a string, such as $[notation \"R[{0}]\"]"
      | None -> None)
  in
  String.Map.of_alist_reduce (library @ named) ~f:(fun _ model -> model)
;;

let find notation name = Map.find notation name

(* The operator between two operands, if the application is written infix. *)
let written_operator location left right =
  let left = Sail_ast.exp_location left in
  let%bind.Option () = Option.some_if (Sail_ast.same_start location left) () in
  let%bind.Option between = Sail_ast.source_between left (Sail_ast.exp_location right) in
  match String.strip between with
  | "@" -> Some "++"
  | operator
    when (not (String.is_empty operator)) && not (String.exists operator ~f:(String.mem "[](){},;"))
    -> Some operator
  | _ -> None
;;
