open Core
open Libsail
open Extraction.Ast
open Type_check

module Encoded_bit = struct
  type t =
    | Constant of char
    | Operand of int
end

let rec vector_parts (E_aux (aux, _) as expression : tannot exp) =
  match aux with
  | E_vector_append (left, right) -> vector_parts left @ vector_parts right
  | E_app (id, [ left; right ]) when String.equal (Sail_ast.id_string id) "bitvector_concat" ->
    vector_parts left @ vector_parts right
  | E_typ (_, nested) -> vector_parts nested
  | _ -> [ expression ]
;;

let clause_bits env (decoder : Decode.t) ({ pattern; body } : Sail_ast.Function_clause.t) =
  let location = Sail_ast.pat_location pattern in
  let constructor, arguments =
    match Sail_ast.constructor_pat pattern with
    | Some result -> result
    | None -> Sail_ast.fail_at location "encode clause must match an instruction constructor"
  in
  if not (String.equal constructor decoder.constructor)
  then Sail_ast.fail_at location "encode clause constructor does not match decode";
  let arguments = Sail_ast.pattern_args arguments in
  if List.length arguments <> List.length decoder.argument_names
  then Sail_ast.fail_at location [%string "encode %{constructor} operand count differs from decode"];
  let positions =
    List.mapi arguments ~f:(fun index argument ->
      match Sail_ast.unwrap_pat argument with
      | P_aux (P_id id, _) -> Sail_ast.id_string id, index
      | pat -> Sail_ast.fail_at (Sail_ast.pat_location pat) "encode operands must be identifiers")
  in
  List.concat_map (vector_parts body) ~f:(fun part ->
    let width = Sail_ast.width_of_exp env part in
    match part with
    | E_aux (E_id id, (location, _)) ->
      (match List.Assoc.find positions (Sail_ast.id_string id) ~equal:String.equal with
       | Some index -> List.init width ~f:(fun _ -> Encoded_bit.Operand index)
       | None -> Sail_ast.fail_at location "encode uses an identifier outside its operands")
    | E_aux (E_lit (L_aux ((L_bin _ | L_hex _), _) as literal), (location, _)) ->
      let bits = Sail_ast.literal_bits location literal in
      if String.length bits <> width
      then Sail_ast.fail_at location "encode literal differs from its typed width";
      String.to_list bits |> List.map ~f:(fun bit -> Encoded_bit.Constant bit)
    | E_aux (_, (location, _)) ->
      Sail_ast.fail_at location "encode body must concatenate operands and bit-vector literals")
;;

let validate env decodes (clauses : Sail_ast.Function_clause.t list) =
  let encoders =
    List.map clauses ~f:(fun ({ pattern; _ } as clause : Sail_ast.Function_clause.t) ->
      let constructor =
        match Sail_ast.constructor_pat pattern with
        | Some (constructor, _) -> constructor
        | None ->
          Sail_ast.fail_at
            (Sail_ast.pat_location pattern)
            "encode clause must match an instruction constructor"
      in
      constructor, clause)
  in
  let names = List.map encoders ~f:fst in
  List.fold
    encoders
    ~init:String.Set.empty
    ~f:(fun seen (name, ({ pattern; _ } : Sail_ast.Function_clause.t)) ->
      if Set.mem seen name
      then Sail_ast.fail_at (Sail_ast.pat_location pattern) "encode contains duplicate constructors";
      Set.add seen name)
  |> ignore;
  let decoded_names = List.map decodes ~f:(fun (item : Decode.t) -> item.constructor) in
  if
    not
      (List.equal
         String.equal
         (List.sort names ~compare:String.compare)
         (List.sort decoded_names ~compare:String.compare))
  then (
    let location =
      match clauses with
      | ({ pattern; _ } : Sail_ast.Function_clause.t) :: _ -> Sail_ast.pat_location pattern
      | [] -> Parse_ast.Unknown
    in
    Sail_ast.fail_at location "encode and decode instruction sets differ");
  List.iter decodes ~f:(fun (decoder : Decode.t) ->
    let clause =
      match List.Assoc.find encoders decoder.constructor ~equal:String.equal with
      | Some clause -> clause
      | None ->
        Sail_ast.fail_at
          decoder.location
          [%string "missing encode clause for %{decoder.constructor}"]
    in
    let bits = clause_bits env decoder clause in
    if List.length bits <> List.length decoder.expected_bits
    then
      Sail_ast.fail_at
        decoder.location
        [%string "encode %{decoder.constructor} has a different word width"];
    List.iter2_exn decoder.expected_bits bits ~f:(fun expected actual ->
      match expected, actual with
      | Decode.Expected_bit.Constant expected, Encoded_bit.Constant actual
        when Char.equal expected actual -> ()
      | Decode.Expected_bit.Operand expected, Encoded_bit.Operand actual
        when Int.equal expected actual -> ()
      | Decode.Expected_bit.Padding, Encoded_bit.Constant '0' -> ()
      | _ ->
        Sail_ast.fail_at
          decoder.location
          [%string "encode %{decoder.constructor} does not match its decode layout"]))
;;
