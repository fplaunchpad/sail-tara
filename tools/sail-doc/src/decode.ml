open Core
open Libsail
open Extraction.Ast

type t =
  { constructor : string
  ; operands : string option list
  ; fields : Word_field.t list
  ; location : Parse_ast.l
  }

(* The fallback is required even when every encoding is assigned: when the clauses cover every
   word, Sail's completeness check turns a fixed field of the last clause into a wildcard. *)
let split_fallback (clauses : Sail_ast.Function_clause.t list) =
  match List.rev clauses with
  | [] -> Sail_ast.fail_at Parse_ast.Unknown "decode has no clauses"
  | fallback :: rest ->
    let clauses = List.rev rest in
    List.iter clauses ~f:(fun clause ->
      if Option.is_none (Sail_ast.decode_result clause.body)
      then Sail_ast.fail_at clause.location "only the last clause of decode may return None()");
    (match Sail_ast.decode_result fallback.body, Sail_ast.unwrap_pat fallback.pattern with
     | None, P_aux (P_wild, _) -> ()
     | _ ->
       Sail_ast.fail_at
         fallback.location
         "decode must end with a wildcard None() clause, even when every encoding is assigned");
    clauses, fallback
;;

let field env pattern : Word_field.t =
  let location = Sail_ast.pat_location pattern in
  let fixed name literal : Word_field.t =
    match Sail_ast.unwrap_pat literal with
    | P_aux (P_lit literal, _) -> Fixed { name; bits = Sail_ast.literal_bits location literal }
    | _ -> Sail_ast.fail_at location "only fixed bits can be named with as"
  in
  match Sail_ast.unwrap_pat pattern with
  | P_aux (P_lit _, _) as literal -> fixed None literal
  | P_aux (P_as (literal, id), _) -> fixed (Some (Sail_ast.id_string id)) literal
  | P_aux (P_id id, _) ->
    Operand { name = Sail_ast.id_string id; width = Sail_ast.width_of_pat env pattern }
  | P_aux (P_wild, _) -> Ignored { width = Sail_ast.width_of_pat env pattern }
  | _ -> Sail_ast.fail_at location "a decode field must be bits, a name or a wildcard"
;;

let instruction env ({ pattern; guarded; body; location; _ } : Sail_ast.Function_clause.t) =
  if guarded then Sail_ast.fail_at location "guarded decode clauses are not supported";
  let constructor, arguments =
    match Sail_ast.decode_result body with
    | Some result -> result
    | None -> Sail_ast.fail_at location "a decode clause must return Some(instruction)"
  in
  let operands =
    List.map arguments ~f:(function
      | E_aux (E_id id, _) -> Some (Sail_ast.id_string id)
      | _ -> None)
  in
  let fields =
    match Sail_ast.unwrap_pat pattern with
    | P_aux (P_vector_concat parts, _) -> List.map parts ~f:(field env)
    | _ -> [ field env pattern ]
  in
  ({ constructor; operands; fields; location } : t)
;;

(* The word with the fixed bits in place and dashes elsewhere, which identifies an encoding. *)
let encoding { fields; _ } =
  List.map fields ~f:(fun field ->
    match field with
    | Fixed { bits; _ } -> bits
    | Operand _ | Ignored _ -> String.make (Word_field.width field) '-')
  |> String.concat
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
  let clauses, fallback = split_fallback clauses in
  let instructions = List.map clauses ~f:(instruction env) in
  check_distinct instructions ~what:"instruction" ~key:(fun { constructor; _ } -> constructor);
  check_distinct instructions ~what:"encoding" ~key:encoding;
  instructions, fallback
;;
