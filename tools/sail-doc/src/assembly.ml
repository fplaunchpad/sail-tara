open Core
open Libsail
open Extraction.Ast

let rec syntax_pieces pattern =
  match Sail_ast.unwrap_mpat pattern with
  | MP_aux (MP_string_append parts, _) -> List.concat_map parts ~f:syntax_pieces
  | piece -> [ piece ]
;;

let extract_one
      ~constants
      (decodes : Decode.t list)
      ({ left; right; location } : Sail_ast.Mapping_clause.t)
  =
  let constructor, arguments =
    match Sail_ast.constructor_mpat left with
    | Some result -> result
    | None ->
      Sail_ast.fail_at location "assembly mapping left side must be an instruction constructor"
  in
  let decoder =
    match
      List.find decodes ~f:(fun (item : Decode.t) -> String.equal item.constructor constructor)
    with
    | Some decoder -> decoder
    | None ->
      Sail_ast.fail_at
        location
        [%string "assembly constructor %{constructor} is absent from decode"]
  in
  let arguments =
    match arguments with
    | [ MP_aux (MP_lit (L_aux (L_unit, _)), _) ] -> []
    | [ MP_aux (MP_tuple arguments, _) ] -> arguments
    | arguments -> arguments
  in
  if List.length arguments <> List.length decoder.argument_names
  then
    Sail_ast.fail_at location [%string "assembly %{constructor} operand count differs from decode"];
  let assembly_positions =
    List.mapi arguments ~f:(fun index argument ->
      match Sail_ast.unwrap_mpat argument with
      | MP_aux (MP_id id, _) -> Sail_ast.id_string id, index
      | pattern ->
        Sail_ast.fail_at
          (Sail_ast.mpat_location pattern)
          "assembly constructor operands must be identifiers")
  in
  let pieces = syntax_pieces right in
  let syntax =
    List.map pieces ~f:(fun piece ->
      let piece = Sail_ast.unwrap_mpat piece in
      match piece with
      | MP_aux (MP_lit (L_aux (L_string text, _)), _) -> text
      | MP_aux (MP_app (_, [ MP_aux (MP_id binder, _) ]), _) ->
        let binder = Sail_ast.id_string binder in
        (match List.Assoc.find assembly_positions binder ~equal:String.equal with
         | None ->
           Sail_ast.fail_at
             (Sail_ast.mpat_location piece)
             [%string "assembly formatter refers to unknown operand %{binder}"]
         | Some index ->
           (match List.nth decoder.argument_names index with
            | Some name -> name
            | None -> Sail_ast.fail_at location "assembly operand position is outside decode"))
      | _ ->
        (match Constant.eval constants piece with
         | Ok text -> text
         | Error error ->
           Sail_ast.fail_at (Sail_ast.mpat_location piece) (Error.to_string_hum error)))
    |> String.concat ~sep:""
  in
  if String.is_empty syntax
  then Sail_ast.fail_at location [%string "assembly syntax for %{constructor} is empty"];
  constructor, syntax
;;

let extract ~constants (decodes : Decode.t list) (clauses : Sail_ast.Mapping_clause.t list) =
  let syntax = List.map clauses ~f:(extract_one ~constants decodes) in
  let names = List.map syntax ~f:fst in
  if List.length names <> List.length (List.dedup_and_sort names ~compare:String.compare)
  then
    Sail_ast.fail_at
      (match clauses with
       | ({ location; _ } : Sail_ast.Mapping_clause.t) :: _ -> location
       | [] -> Parse_ast.Unknown)
      "assembly mapping contains duplicate instruction constructors";
  let decoded_names = List.map decodes ~f:(fun (item : Decode.t) -> item.constructor) in
  let names = List.dedup_and_sort names ~compare:String.compare in
  let decoded_names = List.dedup_and_sort decoded_names ~compare:String.compare in
  if not (List.equal String.equal names decoded_names)
  then
    Sail_ast.fail_at
      (match clauses with
       | ({ location; _ } : Sail_ast.Mapping_clause.t) :: _ -> location
       | [] -> Parse_ast.Unknown)
      "assembly mapping and decode instruction sets differ";
  syntax
;;
