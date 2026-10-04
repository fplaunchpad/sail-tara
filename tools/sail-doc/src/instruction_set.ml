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
    ; execution : string list
    }
  [@@deriving yojson_of]
end

type t =
  { word_width : int
  ; instructions : Instruction.t list
  ; outline : Outline.t
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

let read ~ast ~env ~encdec ~assembly ~execute =
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
  let instructions =
    List.map encodings ~f:(fun encoding ->
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
       ; execution = Execution.read ~env ~functions ~execute encoding |> required execute
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
  { word_width; instructions; outline }
;;
