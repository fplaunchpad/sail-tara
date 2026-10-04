open Core
open Libsail
open Extraction.Ast

type t =
  { constructor : string
  ; operands : string list
  ; opcode : string
  ; fields : Word_field.t list
  ; location : Parse_ast.l
  }

(* The fallback is required even when every opcode is assigned: when the clauses cover every word,
   Sail's completeness check turns the last clause's opcode into a wildcard. *)
let rec check_fallback : Sail_ast.Function_clause.t list -> unit = function
  | [] ->
    Sail_ast.fail_at
      Parse_ast.Unknown
      "decode must end with a wildcard None() clause, even when every opcode is assigned"
  | { pattern; body } :: rest ->
    (match Sail_ast.decode_result body, Sail_ast.unwrap_pat pattern, rest with
     | Some _, _, _ -> check_fallback rest
     | None, P_aux (P_wild, _), [] -> ()
     | None, _, _ ->
       Sail_ast.fail_at
         (Sail_ast.pat_location pattern)
         "the only None() clause of decode must be the last, and match anything")
;;

let field env ~constructor ~operands pattern : Word_field.t =
  let pattern = Sail_ast.unwrap_pat pattern in
  let location = Sail_ast.pat_location pattern in
  let width = Sail_ast.width_of_pat env pattern in
  match pattern with
  | P_aux (P_wild, _) -> { name = Word_field.padding; width }
  | P_aux (P_id id, _) ->
    let name = Sail_ast.id_string id in
    if List.mem [ Word_field.opcode; Word_field.padding ] name ~equal:String.equal
    then Sail_ast.fail_at location [%string "%{name} is a reserved field name"];
    if not (List.mem operands name ~equal:String.equal)
    then Sail_ast.fail_at location [%string "%{name} is not an operand of %{constructor}"];
    { name; width }
  | P_aux (P_lit _, _) ->
    Sail_ast.fail_at location "fixed bits are only supported at the start of a word"
  | _ -> Sail_ast.fail_at location "a decode field must be a name or a wildcard"
;;

let instruction env ({ pattern; body } : Sail_ast.Function_clause.t) =
  let%map.Option constructor, operands = Sail_ast.decode_result body in
  let location = Sail_ast.pat_location pattern in
  match Sail_ast.unwrap_pat pattern with
  | P_aux (P_vector_concat (first :: rest), _) ->
    let opcode =
      match Sail_ast.unwrap_pat first with
      | P_aux (P_lit literal, _) -> Sail_ast.literal_bits location literal
      | _ -> Sail_ast.fail_at location "a decode clause must start with the opcode's bits"
    in
    let fields = List.map rest ~f:(field env ~constructor ~operands) in
    ({ constructor
     ; operands
     ; opcode
     ; fields = { name = Word_field.opcode; width = String.length opcode } :: fields
     ; location
     }
     : t)
  | _ -> Sail_ast.fail_at location "a decode clause must match a concatenation of fields"
;;

let check_distinct instructions ~what ~key =
  ignore
    (List.fold instructions ~init:String.Set.empty ~f:(fun seen (instruction : t) ->
       let value = key instruction in
       if Set.mem seen value
       then
         Sail_ast.fail_at
           instruction.location
           [%string "decode has two clauses for %{what} %{value}"];
       Set.add seen value)
     : String.Set.t)
;;

let read env clauses =
  check_fallback clauses;
  let instructions = List.filter_map clauses ~f:(instruction env) in
  check_distinct instructions ~what:"instruction" ~key:(fun { constructor; _ } -> constructor);
  check_distinct instructions ~what:"opcode" ~key:(fun { opcode; _ } -> opcode);
  match instructions with
  | [] -> Sail_ast.fail_at Parse_ast.Unknown "decode has no instruction clauses"
  | { opcode; _ } :: _ ->
    List.iter instructions ~f:(fun instruction ->
      if String.length instruction.opcode <> String.length opcode
      then Sail_ast.fail_at instruction.location "decode's opcodes differ in width");
    instructions
;;
