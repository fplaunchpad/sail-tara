open Core
open Libsail
open Extraction.Ast

module Expected_bit = struct
  type t =
    | Constant of char
    | Operand of int
    | Padding
end

type t =
  { constructor : string
  ; opcode_bits : string
  ; fields : Instruction.Field.t list
  ; argument_names : string list
  ; expected_bits : Expected_bit.t list
  ; location : Parse_ast.l
  ; source_file : string
  }

module Pattern_part = struct
  type t =
    | Literal of string
    | Bound of string
    | Ignored
end

let pattern_parts env pattern =
  match Sail_ast.unwrap_pat pattern with
  | P_aux (P_vector_concat parts, _) when not (List.is_empty parts) ->
    List.map parts ~f:(fun part ->
      let part = Sail_ast.unwrap_pat part in
      let width = Sail_ast.width_of_pat env part in
      let location = Sail_ast.pat_location part in
      let kind =
        match part with
        | P_aux (P_lit literal, _) -> Pattern_part.Literal (Sail_ast.literal_bits location literal)
        | P_aux (P_id id, _) -> Pattern_part.Bound (Sail_ast.id_string id)
        | P_aux (P_wild, _) -> Pattern_part.Ignored
        | _ -> Sail_ast.fail_at location "decode fields must be literals, identifiers, or wildcards"
      in
      match kind with
      | Pattern_part.Literal bits when String.length bits <> width ->
        Sail_ast.fail_at location "literal width differs from its typed width"
      | _ -> width, kind, location)
  | _ ->
    Sail_ast.fail_at
      (Sail_ast.pat_location pattern)
      "decode clause must match a concatenated word pattern"
;;

let extract_one env ({ pattern; body } : Sail_ast.Function_clause.t) =
  let location = Sail_ast.pat_location pattern in
  match Sail_ast.decode_result body with
  | None -> None
  | Some (constructor, argument_names) ->
    let parts = pattern_parts env pattern in
    let opcode_bits =
      match parts with
      | (_, Pattern_part.Literal bits, _) :: _ -> bits
      | _ -> Sail_ast.fail_at location "decode clause must begin with a fixed opcode literal"
    in
    let unique_names = List.dedup_and_sort argument_names ~compare:String.compare in
    if List.length argument_names <> List.length unique_names
    then Sail_ast.fail_at location "decode constructor operands must have unique field names";
    let argument_positions = List.mapi argument_names ~f:(fun index name -> name, index) in
    let fields =
      List.mapi parts ~f:(fun index (width, part, part_location) ->
        let name =
          match index, part with
          | 0, Pattern_part.Literal _ -> "opcode"
          | 0, _ -> Sail_ast.fail_at part_location "first decode field must be the opcode literal"
          | _, Pattern_part.Bound name ->
            if String.equal name "opcode" || String.equal name "padding"
            then Sail_ast.fail_at part_location [%string "decode field name %{name} is reserved"];
            name
          | _, Pattern_part.Ignored -> "padding"
          | _, Pattern_part.Literal _ ->
            Sail_ast.fail_at part_location "fixed fields after the opcode are unsupported"
        in
        ({ name; width } : Instruction.Field.t))
    in
    let expected_bits =
      List.concat_map parts ~f:(fun (width, part, part_location) ->
        match part with
        | Pattern_part.Literal bits ->
          String.to_list bits |> List.map ~f:(fun bit -> Expected_bit.Constant bit)
        | Pattern_part.Ignored -> List.init width ~f:(fun _ -> Expected_bit.Padding)
        | Pattern_part.Bound name ->
          (match List.Assoc.find argument_positions name ~equal:String.equal with
           | Some index -> List.init width ~f:(fun _ -> Expected_bit.Operand index)
           | None ->
             Sail_ast.fail_at
               part_location
               [%string "decoded field %{name} is not passed to %{constructor}"]))
    in
    Some
      ({ constructor
       ; opcode_bits
       ; fields
       ; argument_names
       ; expected_bits
       ; location
       ; source_file = Sail_ast.source_file location
       }
       : t)
;;

let extract env (clauses : Sail_ast.Function_clause.t list) =
  (* Even when every opcode is assigned, the fallback is required: when the clauses cover every
     word, Sail's completeness check turns the last clause's opcode into a wildcard. *)
  let rec validate_fallback = function
    | [] ->
      Sail_ast.fail_at
        Parse_ast.Unknown
        "decode must end with a wildcard None() clause, even when every opcode is assigned"
    | ({ pattern; body } : Sail_ast.Function_clause.t) :: remaining ->
      (match Sail_ast.decode_result body with
       | Some _ -> validate_fallback remaining
       | None ->
         (match Sail_ast.unwrap_pat pattern, remaining with
          | P_aux (P_wild, _), [] -> ()
          | _ ->
            Sail_ast.fail_at
              (Sail_ast.pat_location pattern)
              "None() must be the final wildcard decode clause"))
  in
  validate_fallback clauses;
  let decoded = List.filter_map clauses ~f:(extract_one env) in
  let first =
    match decoded with
    | first :: _ -> first
    | [] -> Sail_ast.fail_at Parse_ast.Unknown "decode has no concrete instruction clauses"
  in
  let check_unique ~f message =
    List.fold decoded ~init:String.Set.empty ~f:(fun seen clause ->
      let value = f clause in
      if Set.mem seen value then Sail_ast.fail_at clause.location message;
      Set.add seen value)
    |> ignore
  in
  check_unique ~f:(fun clause -> clause.constructor) "decode contains duplicate constructors";
  check_unique ~f:(fun clause -> clause.opcode_bits) "decode contains duplicate opcodes";
  let word_width = List.length first.expected_bits in
  let opcode_width = String.length first.opcode_bits in
  List.iter decoded ~f:(fun clause ->
    if List.length clause.expected_bits <> word_width
    then Sail_ast.fail_at clause.location "decode clauses have different word widths";
    if String.length clause.opcode_bits <> opcode_width
    then Sail_ast.fail_at clause.location "decode clauses have different opcode widths");
  decoded
;;
