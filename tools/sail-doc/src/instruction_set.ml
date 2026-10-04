open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Instruction = struct
  type t =
    { constructor : string
    ; operand_count : int
    ; syntax : string
    ; fields : Word_field.t list
    ; clauses : Clause.t list
    }
  [@@deriving yojson_of]
end

module Fallback = struct
  type t =
    { name : string [@key "function"]
    ; documented : bool
    }
  [@@deriving yojson_of]
end

type t =
  { word_width : int
  ; instructions : Instruction.t list
  ; outline : Outline.t
  ; fallback : Fallback.t
  }
[@@deriving yojson_of]

(* The constructors of the union that the assembly mapping maps to text, with their locations. *)
let constructors env ~assembly =
  let location = Parse_ast.Unknown in
  let _, mapping = Type_check.Env.get_val_spec (Ast_util.mk_id assembly) env in
  match mapping with
  | Typ_aux (Typ_bidir (instruction, _), _) ->
    (match Type_check.Env.expand_synonyms env instruction with
     | Typ_aux (Typ_id union, _) ->
       (match Ast_compare.Bindings.find_opt union (Type_check.Env.get_variants env) with
        | Some (_, constructors) ->
          List.map constructors ~f:(fun (Tu_aux (Tu_ty_id (_, id), annot)) ->
            Sail_ast.id_string id, annot.loc)
        | None -> Sail_ast.fail_at location [%string "%{assembly} must map a union to text"])
     | _ -> Sail_ast.fail_at location [%string "%{assembly} must map a union to text"])
  | _ -> Sail_ast.fail_at location [%string "%{assembly} must be a mapping"]
;;

let read ~ast ~env ~decode ~assembly =
  let decoded, fallback =
    Sail_ast.function_clauses ast
    |> List.filter ~f:(fun ({ name; _ } : Sail_ast.Function_clause.t) -> String.equal name decode)
    |> Decode.read env
  in
  let syntaxes = Syntax.read ~mappings:(Sail_ast.mapping_clauses ast) ~assembly decoded in
  let constructors = constructors env ~assembly in
  let clauses =
    Clause.read ~ast ~constructors:(List.map constructors ~f:fst |> String.Set.of_list)
  in
  let instructions =
    List.map constructors ~f:(fun (constructor, location) ->
      let missing function_name =
        Sail_ast.fail_at location [%string "%{function_name} has no clause for %{constructor}"]
      in
      let ({ operands; fields; _ } : Decode.t) =
        match
          List.find decoded ~f:(fun instruction -> String.equal instruction.constructor constructor)
        with
        | Some instruction -> instruction
        | None -> missing decode
      in
      let syntax =
        match List.Assoc.find syntaxes constructor ~equal:String.equal with
        | Some syntax -> syntax
        | None -> missing assembly
      in
      ({ constructor
       ; operand_count = List.length operands
       ; syntax
       ; fields
       ; clauses = Map.find clauses constructor |> Option.value ~default:[]
       }
       : Instruction.t))
  in
  let word_width =
    match decoded with
    | { fields; _ } :: _ -> List.sum (module Int) fields ~f:Word_field.width
    | [] -> 0
  in
  { word_width
  ; instructions
  ; outline = Outline.read ~ast ~constructors
  ; fallback = { name = decode; documented = fallback.documented }
  }
;;
