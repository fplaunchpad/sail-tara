open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Rule = struct
  type t =
    { direction : string
    ; input : string
    ; output : Operation.Expression.t
    ; guard : Operation.Expression.t option
    }
  [@@deriving yojson_of]
end

type t =
  { name : string
  ; title : string
  ; signature : string
  ; description : string
  ; operation : Operation.t list
  ; rules : Rule.t list
  ; dependencies : string list
  ; source_kind : string
  ; documented : bool
  ; source : string
  }
[@@deriving yojson_of]

let rec mapping_expression ~env ~notation (MP_aux (aux, (location, _)) as pattern) =
  let read = mapping_expression ~env ~notation in
  let width = Type_check.typ_of_mpat pattern |> Sail_ast.bits_width env in
  match aux with
  | MP_id id -> Operation.Expression.Value { text = Sail_ast.id_string id; width }
  | MP_lit literal -> Value { text = Ast_util.string_of_lit literal; width }
  | MP_typ (pattern, _) | MP_as (pattern, _) -> read pattern
  | MP_app (id, arguments) ->
    Call
      { name = Sail_ast.id_string id
      ; arguments = List.map arguments ~f:read
      ; width
      ; notation = None
      }
  | MP_string_append arguments ->
    Call { name = "concat_str"; arguments = List.map arguments ~f:read; width; notation = None }
  | MP_vector_concat arguments ->
    Call
      { name = "bitvector_concat"; arguments = List.map arguments ~f:read; width; notation = None }
  | _ -> Sail_ast.fail_at location "documentation cannot describe this mapping pattern"
;;

let read ~ast ~env ~notation ~roots ~calls =
  let functions = Sail_ast.function_clauses ast in
  let directory =
    List.find_map ast.defs ~f:(function
      | DEF_aux (DEF_val (VS_aux (VS_val_spec (_, id, _), _)), annot)
        when List.mem roots (Sail_ast.id_string id) ~equal:String.equal ->
        Some (Filename.dirname (Sail_ast.source_file annot.loc) ^ "/")
      | _ -> None)
  in
  let definitions =
    List.filter_map ast.defs ~f:(fun (DEF_aux (definition, annot)) ->
      let%bind.Option name, source_kind =
        match definition with
        | DEF_fundef (FD_aux (FD_function (_, _, FCL_aux (FCL_funcl (id, _), _) :: _), _)) ->
          Some (Sail_ast.id_string id, "function")
        | DEF_mapdef (MD_aux (MD_mapping (id, _, _), _)) -> Some (Sail_ast.id_string id, "mapping")
        | _ -> None
      in
      let doc = Documentation.helper annot in
      let owned =
        Option.value_map directory ~default:false ~f:(fun directory ->
          Option.is_some (Reporting.simp_loc annot.loc)
          && String.is_prefix (Sail_ast.source_file annot.loc) ~prefix:directory)
      in
      Option.some_if (Option.is_some doc || owned) (name, source_kind, definition, annot, doc))
  in
  let extract
        ( name
        , source_kind
        , definition
        , (annot : Type_check.env def_annot)
        , (doc : Documentation.Helper.t option) )
    =
    let quant, typ = Type_check.Env.get_val_spec (Ast_util.mk_id name) env in
    let specification =
      List.find_map ast.defs ~f:(function
        | DEF_aux (DEF_val (VS_aux (VS_val_spec (_, id, _), _)), annot)
          when String.equal name (Sail_ast.id_string id) -> Some annot
        | _ -> None)
    in
    let signature =
      Option.bind specification ~f:(fun annot ->
        let source = Sail_ast.source_text annot.loc in
        if String.is_prefix source ~prefix:"val "
        then String.lsplit2 source ~on:':' |> Option.map ~f:(fun (_, typ) -> String.strip typ)
        else None)
      |> Option.value
           ~default:
             (if List.is_empty quant
              then Ast_util.string_of_typ typ
              else Ast_util.string_of_typschm (Ast_util.mk_typschm quant typ))
    in
    let operation =
      if List.mem roots name ~equal:String.equal
      then []
      else (
        let clauses =
          List.filter functions ~f:(fun ({ name = candidate; _ } : Sail_ast.Function_clause.t) ->
            String.equal name candidate)
        in
        if List.length clauses > 1
        then
          Sail_ast.fail_at
            annot.loc
            "helper documentation needs structured support for multiple function patterns";
        List.concat_map clauses ~f:(fun ({ body; guard; _ } : Sail_ast.Function_clause.t) ->
          let bindings = String.Map.empty in
          let body = Operation.statements ~env ~notation ~bindings body in
          match guard with
          | None -> body
          | Some guard ->
            [ Operation.Branch
                { condition = Operation.expression ~env ~notation ~bindings guard
                ; yes = body
                ; no = []
                }
            ]))
    in
    let rules =
      match definition with
      | DEF_mapdef (MD_aux (MD_mapping (_, _, clauses), _)) ->
        let side (MPat_aux (side, _)) =
          match side with
          | MPat_pat pattern -> pattern, None
          | MPat_when (pattern, guard) -> pattern, Some guard
        in
        let read = Operation.expression ~env ~notation ~bindings:String.Map.empty in
        List.concat_map clauses ~f:(fun (MCL_aux (clause, _)) ->
          match clause with
          | MCL_bidir (left, right) ->
            let left, left_guard = side left in
            let right, right_guard = side right in
            let rule direction input output guard =
              ({ direction
               ; input = Ast_util.string_of_mpat input
               ; output = mapping_expression ~env ~notation output
               ; guard = Option.map guard ~f:read
               }
               : Rule.t)
            in
            [ rule "Encode / print" left right left_guard
            ; rule "Decode / parse" right left right_guard
            ]
          | (MCL_forwards (Pat_aux (clause, _)) | MCL_backwards (Pat_aux (clause, _))) as
            mapping_clause ->
            let direction =
              match mapping_clause with
              | MCL_forwards _ -> "Encode / print"
              | _ -> "Decode / parse"
            in
            let pattern, guard, output =
              match clause with
              | Pat_exp (pattern, output) -> pattern, None, output
              | Pat_when (pattern, guard, output) -> pattern, Some guard, output
            in
            [ ({ direction
               ; input = Ast_util.string_of_pat pattern
               ; output = read output
               ; guard = Option.map guard ~f:read
               }
               : Rule.t)
            ])
      | _ -> []
    in
    let description =
      Option.first_some
        annot.doc_comment
        (Option.bind specification ~f:(fun annot -> annot.doc_comment))
      |> Option.value_map ~default:"" ~f:(fun comment -> comment.contents)
    in
    { name
    ; title = Option.value_map doc ~default:name ~f:(fun doc -> doc.title)
    ; signature
    ; description =
        description ^ "\n" ^ Option.value_map doc ~default:"" ~f:(fun doc -> doc.description)
    ; operation
    ; rules
    ; dependencies =
        List.concat_map
          (operation
           @ List.concat_map rules ~f:(fun rule ->
             Operation.Evaluate { value = rule.output }
             :: Option.to_list
                  (Option.map rule.guard ~f:(fun value -> Operation.Evaluate { value }))))
          ~f:Operation.calls
        |> List.dedup_and_sort ~compare:String.compare
    ; source_kind
    ; documented = Option.is_some annot.doc_comment
    ; source = Sail_ast.source_text annot.loc
    }
  in
  let rec collect names found =
    match names with
    | [] -> found
    | name :: rest when Map.mem found name || List.mem roots name ~equal:String.equal ->
      collect rest found
    | name :: rest ->
      (match
         List.find definitions ~f:(fun (candidate, _, _, _, _) -> String.equal name candidate)
       with
       | None -> collect rest found
       | Some definition ->
         let helper = extract definition in
         collect (helper.dependencies @ rest) (Map.set found ~key:name ~data:helper))
  in
  let annotated =
    List.filter_map definitions ~f:(fun (name, _, _, _, doc) -> Option.map doc ~f:(fun _ -> name))
  in
  let found = collect (annotated @ calls) String.Map.empty in
  List.filter_map definitions ~f:(fun (name, _, _, _, _) -> Map.find found name)
;;
