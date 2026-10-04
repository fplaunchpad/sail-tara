open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Instruction = struct
  type t =
    { constructor : string
    ; source_file : string
    ; operand_count : int
    ; opcode_bits : string
    ; syntax : string
    ; fields : Word_field.t list
    }
  [@@deriving yojson_of]
end

type t =
  { word_width : int
  ; instructions : Instruction.t list
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
          List.map constructors ~f:(fun (Tu_aux (Tu_ty_id (_, id), _)) ->
            Sail_ast.id_string id, Ast_util.id_loc id)
        | None -> Sail_ast.fail_at location [%string "%{assembly} must map a union to text"])
     | _ -> Sail_ast.fail_at location [%string "%{assembly} must map a union to text"])
  | _ -> Sail_ast.fail_at location [%string "%{assembly} must be a mapping"]
;;

let read ~ast ~env ~decode ~assembly =
  let decoded = Decode.read env (Sail_ast.function_clauses ast decode) in
  let syntaxes = Syntax.read ~ast decoded (Sail_ast.mapping_clauses ast assembly) in
  let instructions =
    List.map (constructors env ~assembly) ~f:(fun (constructor, location) ->
      let missing function_name =
        Sail_ast.fail_at location [%string "%{function_name} has no clause for %{constructor}"]
      in
      let ({ operands; opcode; fields; location; _ } : Decode.t) =
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
       ; source_file = Sail_ast.source_file location
       ; operand_count = List.length operands
       ; opcode_bits = opcode
       ; syntax
       ; fields
       }
       : Instruction.t))
    |> List.sort ~compare:(fun (left : Instruction.t) right ->
      String.compare left.opcode_bits right.opcode_bits)
  in
  let word_width =
    match decoded with
    | { fields; _ } :: _ -> List.sum (module Int) fields ~f:(fun { width; _ } -> width)
    | [] -> 0
  in
  { word_width; instructions }
;;
