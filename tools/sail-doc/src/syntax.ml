open Core
open Libsail
open Extraction.Ast

let rec template ~env ~mappings ~lookup pattern =
  let location = Sail_ast.mpat_location pattern in
  match Sail_ast.unwrap_mpat pattern with
  | MP_aux (MP_lit (L_aux (L_string text, _)), _) -> text
  | MP_aux (MP_string_append parts, _) ->
    List.map parts ~f:(template ~env ~mappings ~lookup) |> String.concat
  | MP_aux (MP_app (mapping, [ argument ]), _) ->
    let mapping = Sail_ast.id_string mapping in
    (* The text of the clause of the mapping for a constant, such as a mnemonic or a separator. *)
    let inline constant =
      let clause =
        List.find mappings ~f:(fun ({ name; left; _ } : Sail_ast.Mapping_clause.t) ->
          String.equal name mapping
          && [%equal: Sail_ast.Argument.t] (Sail_ast.Argument.of_mpat env left) (Constant constant))
      in
      match clause with
      | Some { right; _ } ->
        let lookup binder =
          Sail_ast.fail_at location [%string "%{mapping} prints %{binder}, which is not an operand"]
        in
        template ~env ~mappings ~lookup right
      | None -> Sail_ast.fail_at location [%string "%{mapping} has no clause for %{constant}"]
    in
    (match Sail_ast.Argument.of_mpat env argument with
     | Constant constant -> inline constant
     | Binder binder ->
       (match (lookup binder : Encoding.Argument.t) with
        | Operand name -> name
        | Constant constant -> inline constant)
     | Wildcard | Other ->
       Sail_ast.fail_at location "a mapping in assembly syntax must print an operand or a constant")
  | _ -> Sail_ast.fail_at location "assembly syntax must concatenate strings and mappings"
;;

let read ~env ~mappings ~assembly (instruction : Encoding.t) =
  List.find_map mappings ~f:(fun ({ name; left; right; _ } : Sail_ast.Mapping_clause.t) ->
    let%bind.Option () = Option.some_if (String.equal name assembly) () in
    let%bind.Option constructor, patterns = Sail_ast.constructor_mpat left in
    let patterns = List.map patterns ~f:(Sail_ast.Argument.of_mpat env) in
    let%map.Option bindings = Encoding.bindings instruction (constructor, patterns) in
    let lookup binder =
      match List.Assoc.find bindings binder ~equal:String.equal with
      | Some argument -> argument
      | None ->
        Sail_ast.fail_at
          (Sail_ast.mpat_location right)
          [%string "%{binder} is not an operand of %{constructor}"]
    in
    template ~env ~mappings ~lookup right)
;;
