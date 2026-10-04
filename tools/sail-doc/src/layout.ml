open Core
open Libsail
open Extraction.Ast

type t = Metadata.t

let union_constructors env assembly_name location =
  let mapping_id = Ast_util.mk_id assembly_name in
  let _, mapping_type = Type_check.Env.get_val_spec mapping_id env in
  let union_type =
    match mapping_type with
    | Typ_aux (Typ_bidir (union_type, output_type), _) ->
      (match Type_check.Env.expand_synonyms env output_type with
       | Typ_aux (Typ_id output_id, _) when String.equal (Sail_ast.id_string output_id) "string" ->
         Type_check.Env.expand_synonyms env union_type
       | _ ->
         Sail_ast.fail_at
           location
           [%string "%{assembly_name} must map an instruction type to string"])
    | _ ->
      Sail_ast.fail_at
        location
        [%string "%{assembly_name} must be a bidirectional instruction-to-string mapping"]
  in
  let union_id =
    match union_type with
    | Typ_aux (Typ_id id, _) -> id
    | _ ->
      Sail_ast.fail_at
        location
        [%string "the input type of %{assembly_name} must be an instruction union"]
  in
  let variants = Type_check.Env.get_variants env in
  let constructors =
    match Ast_compare.Bindings.find_opt union_id variants with
    | Some (_, constructors) -> constructors
    | None ->
      Sail_ast.fail_at location [%string "the input type of %{assembly_name} is not a Sail union"]
  in
  List.map constructors ~f:(function Tu_aux (Tu_ty_id (_, id), _) -> Sail_ast.id_string id)
;;

let validate_constructors source expected actual location =
  let expected = List.dedup_and_sort expected ~compare:String.compare in
  let actual = List.dedup_and_sort actual ~compare:String.compare in
  if not (List.equal String.equal expected actual)
  then Sail_ast.fail_at location [%string "%{source} does not cover the instruction union"]
;;

let first_decode_location decodes =
  match decodes with
  | ({ location; _ } : Decode.t) :: _ -> location
  | [] -> Sail_ast.fail_at Parse_ast.Unknown "decode has no concrete instruction clauses"
;;

let first_mapping_location clauses =
  match clauses with
  | ({ location; _ } : Sail_ast.Mapping_clause.t) :: _ -> location
  | [] -> Sail_ast.fail_at Parse_ast.Unknown "assembly mapping has no clauses"
;;

let extract ~ast ~env ~constants ~decode_name ~encode_name ~assembly_name =
  let decode_clauses = Sail_ast.function_clauses ast decode_name in
  let encode_clauses = Sail_ast.function_clauses ast encode_name in
  let assembly_clauses = Sail_ast.mapping_clauses ast assembly_name in
  if List.is_empty decode_clauses
  then Sail_ast.fail_at Parse_ast.Unknown [%string "no clauses found for %{decode_name}"];
  if List.is_empty encode_clauses
  then Sail_ast.fail_at Parse_ast.Unknown [%string "no clauses found for %{encode_name}"];
  if List.is_empty assembly_clauses
  then Sail_ast.fail_at Parse_ast.Unknown [%string "no clauses found for %{assembly_name}"];
  let decodes = Decode.extract env decode_clauses in
  let union = union_constructors env assembly_name (first_mapping_location assembly_clauses) in
  validate_constructors
    "decode"
    union
    (List.map decodes ~f:(fun (item : Decode.t) -> item.constructor))
    (first_decode_location decodes);
  Encode.validate env decodes encode_clauses;
  let syntax = Assembly.extract ~constants decodes assembly_clauses in
  validate_constructors
    "assembly mapping"
    union
    (List.map syntax ~f:fst)
    (first_mapping_location assembly_clauses);
  let instructions =
    List.map decodes ~f:(fun (decoded : Decode.t) ->
      let syntax =
        match List.Assoc.find syntax decoded.constructor ~equal:String.equal with
        | Some syntax -> syntax
        | None ->
          Sail_ast.fail_at
            decoded.location
            [%string "missing assembly syntax for %{decoded.constructor}"]
      in
      ({ constructor = decoded.constructor
       ; opcode_bits = decoded.opcode_bits
       ; syntax
       ; fields = decoded.fields
       }
       : Instruction.t))
    |> List.sort ~compare:(fun left right -> String.compare left.opcode_bits right.opcode_bits)
  in
  let word_width =
    match decodes with
    | first :: _ ->
      List.sum (module Int) first.fields ~f:(fun ({ width; _ } : Instruction.Field.t) -> width)
    | [] -> Sail_ast.fail_at Parse_ast.Unknown "decode has no concrete instruction clauses"
  in
  ({ word_width; instructions } : Metadata.t)
;;
