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
  ; prose : Prose.t
  ; retirement : Operation.t list
  ; complete : bool
  ; context : Example.Context.t option
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

let read ~(state : Interactive.State.istate) ~encdec ~assembly ~execute ~complete ~examples =
  let ast, env = state.ast, state.env in
  let config = Option.map examples ~f:(Example.Config.read ast) in
  let context = Option.map config ~f:(fun config -> config.context) in
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
      let matching =
        List.find_map
          functions
          ~f:(fun ({ name; pattern; annotation; _ } : Sail_ast.Function_clause.t) ->
            let%bind.Option () = Option.some_if (String.equal name execute) () in
            let%bind.Option constructor, patterns = Sail_ast.constructor_pat pattern in
            let%map.Option _ =
              Encoding.bindings
                encoding
                (constructor, List.map patterns ~f:(Sail_ast.Argument.of_pat env))
            in
            annotation)
      in
      let annotation =
        if Option.is_some (Documentation.read encoding.annotation)
        then encoding.annotation
        else Option.value matching ~default:encoding.annotation
      in
      let documentation = Documentation.read annotation in
      let description = Doc_comment.body annotation in
      Option.iter documentation ~f:(Documentation.validate encoding);
      if complete && Option.is_none documentation
      then
        Sail_ast.fail_at
          encoding.location
          "complete documentation requires @brief for every encoding";
      let syntax = Syntax.read ~env ~mappings ~assembly encoding in
      let examples =
        match config, context, evaluator, syntax with
        | Some config, Some context, Some evaluator, Some syntax ->
          List.find config.instructions ~f:(fun ({ syntax = candidate; _ } : Example.Input.t) ->
            String.equal syntax candidate)
          |> Option.value_map ~default:[] ~f:(fun input ->
            List.map input.examples ~f:(Example.read evaluator ~context ~encdec ~assembly encoding))
        | _ -> []
      in
      let required name = function
        | Some found -> found
        | None ->
          Sail_ast.fail_at
            encoding.location
            [%string "%{name} has no clause for %{Encoding.to_string encoding}"]
      in
      ({ constructor = encoding.constructor
       ; syntax = syntax |> required assembly
       ; fields = encoding.fields
       ; condition = encoding.condition
       ; execution = Execution.read ~env ~notation ~functions ~execute encoding |> required execute
       ; documentation
       ; description
       ; examples
       }
       : Instruction.t))
  in
  List.iter2_exn encodings instructions ~f:(fun encoding instruction ->
    Option.iter instruction.documentation ~f:(fun doc ->
      List.iter doc.related ~f:(fun name ->
        let matches =
          List.count instructions ~f:(fun candidate ->
            let mnemonic =
              String.take_while candidate.syntax ~f:(fun char ->
                Char.is_alphanum char || String.mem "_." char)
            in
            String.equal name mnemonic)
        in
        if matches <> 1
        then
          Sail_ast.fail_at
            encoding.location
            [%string "unknown or ambiguous related instruction %{name}"])));
  Option.iter config ~f:(fun config ->
    List.iter config.instructions ~f:(fun ({ syntax; _ } : Example.Input.t) ->
      let matches =
        List.count instructions ~f:(fun instruction -> String.equal instruction.syntax syntax)
      in
      if matches <> 1
      then
        Sail_ast.fail_at Parse_ast.Unknown [%string "unknown or ambiguous example syntax %{syntax}"]));
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
  { schema_version = 3
  ; word_width
  ; instructions
  ; outline
  ; helpers
  ; prose = Prose.read ast
  ; retirement
  ; complete
  ; context
  }
;;
