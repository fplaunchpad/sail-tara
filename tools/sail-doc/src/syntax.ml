open Core
open Libsail
open Extraction.Ast

let rec template ~mappings ~operand pattern =
  match Sail_ast.unwrap_mpat pattern with
  | MP_aux (MP_lit (L_aux (L_string text, _)), _) -> text
  | MP_aux (MP_string_append parts, _) ->
    List.map parts ~f:(template ~mappings ~operand) |> String.concat
  | MP_aux (MP_app (mapping, [ argument ]), _) when Sail_ast.is_unit_mpat argument ->
    constant ~mappings (Sail_ast.id_string mapping) (Sail_ast.mpat_location pattern)
  | MP_aux (MP_app (_, [ MP_aux (MP_id binder, _) ]), _) -> operand (Sail_ast.id_string binder)
  | piece ->
    Sail_ast.fail_at
      (Sail_ast.mpat_location piece)
      "assembly syntax must concatenate strings, operands and mappings from unit"

(* The text of a mapping from unit, such as a separator. *)
and constant ~mappings name location =
  match
    List.find mappings ~f:(fun ({ name = mapping; left; _ } : Sail_ast.Mapping_clause.t) ->
      String.equal mapping name && Sail_ast.is_unit_mpat left)
  with
  | Some { right; _ } ->
    let operand binder =
      Sail_ast.fail_at location [%string "%{name} prints %{binder}, which is not an operand"]
    in
    template ~mappings ~operand right
  | None -> Sail_ast.fail_at location [%string "%{name} does not map unit to text"]
;;

let read ~mappings ~assembly (instructions : Decode.t list) =
  List.filter mappings ~f:(fun ({ name; _ } : Sail_ast.Mapping_clause.t) ->
    String.equal name assembly)
  |> List.map ~f:(fun { left; right; location; _ } ->
    let constructor, arguments =
      match Sail_ast.constructor_mpat left with
      | Some application -> application
      | None -> Sail_ast.fail_at location "an assembly clause must take an instruction apart"
    in
    let operands =
      match
        List.find instructions ~f:(fun instruction ->
          String.equal instruction.constructor constructor)
      with
      | Some { operands; _ } -> operands
      | None -> Sail_ast.fail_at location [%string "%{constructor} has no decode clause"]
    in
    let binders =
      List.map arguments ~f:(fun argument ->
        match Sail_ast.unwrap_mpat argument with
        | MP_aux (MP_id id, _) -> Sail_ast.id_string id
        | argument ->
          Sail_ast.fail_at (Sail_ast.mpat_location argument) "assembly operands must be names")
    in
    let names =
      match List.zip binders operands with
      | Ok names -> names
      | Unequal_lengths ->
        Sail_ast.fail_at location [%string "%{constructor} has other operands in decode"]
    in
    let operand binder =
      match List.Assoc.find names binder ~equal:String.equal with
      | Some name -> Option.value name ~default:binder
      | None -> Sail_ast.fail_at location [%string "%{binder} is not an operand of %{constructor}"]
    in
    match template ~mappings ~operand right with
    | "" -> Sail_ast.fail_at location [%string "%{constructor} has no assembly syntax"]
    | text -> constructor, text)
;;
