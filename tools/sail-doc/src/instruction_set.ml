open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Instruction = struct
  type t =
    { constructor : string
    ; syntax : string
    ; fields : Word_field.t list
    ; condition : string option
    ; execution : Operation.t list
    ; documentation : Documentation.t option
    ; description : string
    ; examples : Example.t list
    }
  [@@deriving yojson_of]
end

type t =
  { schema_version : int
  ; word_width : int
  ; instructions : Instruction.t list
  ; outline : Outline.t
  ; helpers : Helper.t list
  ; retirement : Operation.t list
  ; complete : bool
  ; context : Documentation.Context.t option
  }
[@@deriving yojson_of]

(* The constructors of the union that the encoding mapping maps to words, with their locations,
   and the width of a word. *)
let signature env ~encdec =
  let fail () = Sail_ast.fail_at Parse_ast.Unknown [%string "%{encdec} must map a union to bits"] in
  match Type_check.Env.get_val_spec (Ast_util.mk_id encdec) env with
  | _, Typ_aux (Typ_bidir (union, word), _) ->
    let constructors =
      match Type_check.Env.expand_synonyms env union with
      | Typ_aux (Typ_id union, _) ->
        (match Ast_compare.Bindings.find_opt union (Type_check.Env.get_variants env) with
         | Some (_, constructors) ->
           List.map constructors ~f:(fun (Tu_aux (Tu_ty_id (_, id), annot)) ->
             Sail_ast.id_string id, annot.loc)
         | None -> fail ())
      | _ -> fail ()
    in
    (match Sail_ast.bits_width env word with
     | Some width -> constructors, width
     | None -> fail ())
  | _ -> fail ()
;;

let read ~(state : Interactive.State.istate) ~encdec ~assembly ~execute =
  let ast, env = state.ast, state.env in
  let context = Documentation.context ast execute in
  let evaluator = Option.map context ~f:(fun _ -> Example.Evaluator.create state) in
  let constructors, word_width = signature env ~encdec in
  let mappings = Sail_ast.mapping_clauses ast in
  let encodings =
    List.filter mappings ~f:(fun { name; _ } -> String.equal name encdec) |> Encoding.read env
  in
  List.iter constructors ~f:(fun (constructor, location) ->
    if
      not (List.exists encodings ~f:(fun encoding -> String.equal encoding.constructor constructor))
    then Sail_ast.fail_at location [%string "%{encdec} has no clause for %{constructor}"]);
  let functions = Sail_ast.function_clauses ast in
  let notation = Notation.read ast in
  let instructions =
    List.map encodings ~f:(fun encoding ->
      let documentation = Documentation.read encoding.annotation in
      let description =
        List.find_map
          functions
          ~f:(fun ({ name; pattern; annotation; _ } : Sail_ast.Function_clause.t) ->
            let%bind.Option () = Option.some_if (String.equal name execute) () in
            let%bind.Option constructor, patterns = Sail_ast.constructor_pat pattern in
            let%bind.Option _ =
              Encoding.bindings
                encoding
                (constructor, List.map patterns ~f:(Sail_ast.Argument.of_pat env))
            in
            let%map.Option comment = annotation.doc_comment in
            comment.contents)
        |> Option.value ~default:""
      in
      Option.iter documentation ~f:(Documentation.validate encoding);
      if
        Option.value_map context ~default:false ~f:(fun context -> context.complete)
        && Option.is_none documentation
      then
        Sail_ast.fail_at
          encoding.location
          "complete documentation requires instruction_doc on every encoding";
      let examples =
        match documentation, context, evaluator with
        | Some doc, Some context, Some evaluator ->
          List.map doc.examples ~f:(Example.read evaluator ~context ~encdec ~assembly encoding)
        | Some _, _, _ ->
          Sail_ast.fail_at encoding.location "instruction examples require doc_examples on execute"
        | None, _, _ -> []
      in
      let required name = function
        | Some found -> found
        | None ->
          Sail_ast.fail_at
            encoding.location
            [%string "%{name} has no clause for %{Encoding.to_string encoding}"]
      in
      ({ constructor = encoding.constructor
       ; syntax = Syntax.read ~env ~mappings ~assembly encoding |> required assembly
       ; fields = encoding.fields
       ; condition = encoding.condition
       ; execution = Execution.read ~env ~notation ~functions ~execute encoding |> required execute
       ; documentation
       ; description
       ; examples
       }
       : Instruction.t))
  in
  let clauses =
    Clause.read ~ast ~env ~constructors:(List.map constructors ~f:fst |> String.Set.of_list)
  in
  let outline =
    Outline.read
      ~ast
      ~constructors:
        (List.map constructors ~f:(fun (name, location) ->
           ({ name; clauses = Map.find_multi clauses name } : Outline.Item.Constructor.t), location))
  in
  let calls =
    List.concat_map instructions ~f:(fun instruction ->
      List.concat_map instruction.Instruction.execution ~f:Operation.calls)
  in
  let helpers = Helper.read ~ast ~env ~notation ~roots:[ encdec; assembly; execute ] ~calls in
  let retirement =
    List.find helpers ~f:(fun helper -> String.equal helper.name "retire")
    |> Option.value_map ~default:[] ~f:(fun helper -> helper.operation)
  in
  { schema_version = 2
  ; word_width
  ; instructions
  ; outline
  ; helpers
  ; retirement
  ; complete = Option.value_map context ~default:false ~f:(fun context -> context.complete)
  ; context
  }
;;
