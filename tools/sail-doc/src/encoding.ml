open Core
open Libsail
open Extraction.Ast

module Argument = struct
  type t =
    | Operand of string
    | Constant of string
end

type t =
  { constructor : string
  ; arguments : Argument.t list
  ; fields : Word_field.t list
  ; condition : string option
  ; location : Parse_ast.l
  ; annotation : unit def_annot
  }

let to_string { constructor; arguments; _ } =
  let arguments =
    List.map arguments ~f:(fun (Operand name | Constant name : Argument.t) -> name)
    |> String.concat ~sep:", "
  in
  [%string "%{constructor}(%{arguments})"]
;;

let bindings { constructor; arguments; _ } (clause_constructor, patterns) =
  let%bind.Option pairs =
    match List.zip patterns arguments with
    | Ok pairs when String.equal constructor clause_constructor -> Some pairs
    | Ok _ | Unequal_lengths -> None
  in
  List.fold_until
    pairs
    ~init:[]
    ~finish:Option.some
    ~f:(fun bindings ((pattern : Sail_ast.Argument.t), (argument : Argument.t)) ->
      match pattern, argument with
      | Binder binder, _ -> Continue ((binder, argument) :: bindings)
      | Wildcard, _ -> Continue bindings
      | Constant expected, Constant given when String.equal expected given -> Continue bindings
      | Constant _, _ | Other, _ -> Stop None)
;;

let argument env pattern : Argument.t =
  match Sail_ast.Argument.of_mpat env pattern with
  | Binder name -> Operand name
  | Constant constant -> Constant constant
  | Wildcard | Other ->
    Sail_ast.fail_at
      (Sail_ast.mpat_location pattern)
      "an instruction's arguments must be names or constants"
;;

(* The type synonym that annotates fixed bits, if any. *)
let rec name (MP_aux (aux, _) : Type_check.tannot mpat) =
  match aux with
  | MP_typ (_, Typ_aux (Typ_id id, _)) -> Some (Sail_ast.id_string id)
  | MP_typ (nested, _) | MP_as (nested, _) -> name nested
  | _ -> None
;;

(* The operand names a pattern binds. *)
let rec binders env pattern =
  match Sail_ast.unwrap_mpat pattern with
  | MP_aux (MP_id id, _) when not (Type_check.is_enum_member id env) -> [ Sail_ast.id_string id ]
  | MP_aux ((MP_app (_, patterns) | MP_tuple patterns | MP_vector_concat patterns), _) ->
    List.concat_map patterns ~f:(binders env)
  | _ -> []
;;

let field env pattern : Word_field.t =
  let location = Sail_ast.mpat_location pattern in
  match Sail_ast.unwrap_mpat pattern with
  | MP_aux (MP_lit literal, _) ->
    Fixed { name = name pattern; bits = Sail_ast.literal_bits location literal }
  | MP_aux ((MP_id _ | MP_app _), _) as part ->
    let width = Sail_ast.width_of_mpat env pattern in
    (match binders env part with
     | [] -> Ignored { width }
     | [ name ] -> Operand { name; width }
     | _ -> Sail_ast.fail_at location "an encoding field may hold one operand")
  | _ -> Sail_ast.fail_at location "an encoding field must be bits, an operand or a mapping"
;;

let instruction env ({ left; right; guards; location; annotation; _ } : Sail_ast.Mapping_clause.t) =
  let constructor, arguments =
    match Sail_ast.constructor_mpat left with
    | Some application -> application
    | None -> Sail_ast.fail_at location "an encoding clause must have an instruction on its left"
  in
  let fields =
    match Sail_ast.unwrap_mpat right with
    | MP_aux (MP_vector_concat parts, _) -> List.map parts ~f:(field env)
    | _ -> [ field env right ]
  in
  let condition =
    match
      List.map guards ~f:(fun guard -> Sail_ast.exp_location guard |> Sail_ast.source_text)
      |> List.dedup_and_sort ~compare:String.compare
    with
    | [] -> None
    | [ guard ] -> Some guard
    | guards ->
      Some (List.map guards ~f:(fun guard -> "(" ^ guard ^ ")") |> String.concat ~sep:" && ")
  in
  ({ constructor
   ; arguments = List.map arguments ~f:(argument env)
   ; fields
   ; condition
   ; location
   ; annotation
   }
   : t)
;;

(* The word with the fixed bits in place and dashes elsewhere. *)
let encoding { fields; _ } =
  List.map fields ~f:(fun field ->
    match field with
    | Fixed { bits; _ } -> bits
    | Operand _ | Ignored _ -> String.make (Word_field.width field) '-')
  |> String.concat
;;

let read env clauses =
  let instructions = List.map clauses ~f:(instruction env) in
  ignore
    (List.fold
       instructions
       ~init:String.Set.empty
       ~f:(fun seen ({ condition; location; _ } as instruction) ->
         let key = encoding instruction in
         if Option.is_none condition && Set.mem seen key
         then Sail_ast.fail_at location [%string "two encodings are %{key}"];
         Set.add seen key)
     : String.Set.t);
  instructions
;;
