open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Observation = struct
  type t =
    { name : string
    ; before : string
    ; after : string
    ; width : int option
    }
  [@@deriving yojson_of]
end

type t =
  { title : string
  ; assembly : string
  ; word : string
  ; observations : Observation.t list
  ; retirement : string
  ; setup : Documentation.State.t list
  ; arguments : string list
  }
[@@deriving yojson_of]

module Evaluator = struct
  type t =
    { ctx : Initial_check.ctx
    ; ast : Type_check.typed_ast
    ; env : Type_check.env
    }

  let create (state : Interactive.State.istate) =
    let ctx, ast, _, env =
      Rewrites.rewrite
        state.ctx
        state.effect_info
        state.env
        (Rewrites.instantiate_rewrites Rewrites.rewrites_interpreter)
        state.ast
    in
    { ctx; ast; env }
  ;;

  let evaluate { ctx; env; _ } location state source =
    let exp =
      try Initial_check.exp_of_string ctx source |> Type_check.infer_exp env with
      | Type_error.Type_error (_, error) ->
        let message, _ = Type_error.string_of_type_error error in
        Sail_ast.fail_at
          location
          [%string "invalid documentation example expression %{source}: %{message}"]
      | Reporting.Fatal_error error ->
        let message =
          match error with
          | Err_general (_, message)
          | Err_todo (_, message)
          | Err_syntax (_, message)
          | Err_syntax_loc (_, message)
          | Err_lex (_, message)
          | Err_type (_, _, message)
          | Err_warning (_, _, message)
          | Err_unreachable (_, _, _, message) -> message
        in
        Sail_ast.fail_at
          location
          [%string "invalid documentation example expression %{source}: %{message}"]
    in
    let rec run remaining frame =
      if remaining = 0
      then Sail_ast.fail_at location "documentation example exceeded 100000 interpreter steps";
      match frame with
      | Interpreter.Done (state, value) -> state, value
      | Fail (_, _, _, _, message) ->
        Sail_ast.fail_at location [%string "documentation example failed: %{message}"]
      | Step _ | Break _ -> run (remaining - 1) (Interpreter.eval_frame frame)
      | Effect_request (out, state, stack, request) ->
        run (remaining - 1) (Interpreter.default_effect_interp out state stack request)
    in
    run 100000 (Interpreter.Step (lazy "", state, Interpreter.Monad.pure exp, []))
  ;;

  let rec zero env typ =
    match Sail_ast.bits_width env typ with
    | Some width -> [%string "sail_zeros(%{width#Int})"]
    | None ->
      (match Type_check.destruct_vector env typ with
       | Some (size, element) ->
         let size = Type_check.big_int_of_nexp size |> Option.value_exn |> Nat_big_num.to_int in
         [%string "vector_init(%{size#Int}, %{zero env element})"]
       | None ->
         (match Type_check.Env.expand_synonyms env typ with
          | Typ_aux (Typ_id id, _) when String.equal (Sail_ast.id_string id) "bool" -> "false"
          | _ ->
            Sail_ast.fail_at
              Parse_ast.Unknown
              "documentation needs an explicit initializer for this register type"))
  ;;

  let initial ({ ast; env; _ } as evaluator) location =
    let state = Interpreter.initial_state ~undef_registers:false ast env !Value.primops in
    let _, global = state in
    let registers =
      List.fold ast.defs ~init:global.registers ~f:(fun registers -> function
        | DEF_aux (DEF_register (DEC_aux (DEC_reg (typ, id, _), _)), _) ->
          let _, value = evaluate evaluator location state (zero env typ) in
          Ast_compare.Bindings.add id value registers
        | _ -> registers)
    in
    fst state, { global with registers }
  ;;

  let set evaluator location state ({ register; index; value } : Documentation.State.t) =
    let target =
      match index with
      | None -> register
      | Some index -> [%string "%{register}[%{index#Int}]"]
    in
    evaluate evaluator location state [%string "{ %{target} = %{value}; () }"] |> fst
  ;;

  let observe (_, (global : Interpreter.gstate)) (specifications : Documentation.Observed.t list) =
    List.concat_map specifications ~f:(fun { register; label } ->
      let value = Ast_compare.Bindings.find (Ast_util.mk_id register) global.registers in
      let scalar name value =
        let width =
          match value with
          | V_bitvector bits -> Some (List.length bits)
          | _ -> None
        in
        name, Value.string_of_value value, width
      in
      match value with
      | V_vector values ->
        let values =
          match Type_check.Env.get_default_order global.typecheck_env with
          | Ord_aux (Ord_inc, _) -> values
          | _ -> List.rev values
        in
        List.mapi values ~f:(fun index value ->
          let hexadecimal = String.drop_prefix (Int.Hex.to_string index) 2 in
          let hexadecimal = String.pad_left (String.uppercase hexadecimal) ~len:3 ~char:'0' in
          let label = String.substr_replace_all label ~pattern:"{index:03X}" ~with_:hexadecimal in
          scalar
            (String.substr_replace_all label ~pattern:"{index}" ~with_:(Int.to_string index))
            value)
      | _ -> [ scalar label value ])
  ;;
end

let read
      evaluator
      ~(context : Documentation.Context.t)
      ~encdec
      ~assembly
      (encoding : Encoding.t)
      (spec : Documentation.Example.t)
  =
  let values =
    match
      List.map spec.operands ~f:(fun ({ name; value } : Documentation.Value.t) -> name, value)
      |> String.Map.of_alist
    with
    | `Ok values -> values
    | `Duplicate_key name ->
      Sail_ast.fail_at encoding.location [%string "duplicate example operand %{name}"]
  in
  let operands =
    List.filter_map encoding.arguments ~f:(function
      | Encoding.Argument.Operand name -> Some name
      | Constant _ -> None)
    |> String.Set.of_list
  in
  if not (Set.equal operands (Map.key_set values))
  then Sail_ast.fail_at encoding.location "example operands must name each instruction operand once";
  let arguments =
    List.map encoding.arguments ~f:(function
      | Encoding.Argument.Constant value -> value
      | Operand name -> Map.find_exn values name)
    |> String.concat ~sep:", "
  in
  let instruction = [%string "%{encoding.constructor}(%{arguments})"] in
  let setup =
    List.fold (context.initial @ spec.before) ~init:[] ~f:(fun setup state ->
      List.filter setup ~f:(fun earlier ->
        not
          (String.equal earlier.Documentation.State.register state.register
           && [%equal: int option] earlier.index state.index))
      @ [ state ])
  in
  let state = Evaluator.initial evaluator encoding.location in
  let state = List.fold setup ~init:state ~f:(Evaluator.set evaluator encoding.location) in
  let state, printed =
    Evaluator.evaluate
      evaluator
      encoding.location
      state
      [%string "(%{assembly}(%{instruction}), %{encdec}(%{instruction}))"]
  in
  let assembly, word =
    match printed with
    | V_tuple [ V_string text; word ] -> text, Value.string_of_value word
    | _ -> Sail_ast.fail_at encoding.location "example assembly and encoding have unexpected types"
  in
  let before = Evaluator.observe state context.observed in
  List.iter spec.watch ~f:(fun name ->
    if not (List.exists before ~f:(fun (label, _, _) -> String.equal label name))
    then Sail_ast.fail_at encoding.location [%string "unknown example observation %{name}"]);
  let arguments = if List.is_empty spec.arguments then context.arguments else spec.arguments in
  let call_arguments = String.concat ~sep:", " (arguments @ [ instruction ]) in
  let after_state, result =
    Evaluator.evaluate
      evaluator
      encoding.location
      state
      [%string "%{context.runner}(%{call_arguments})"]
  in
  let after = Evaluator.observe after_state context.observed in
  let observations =
    List.map2_exn before after ~f:(fun (name, before, width) (_, after, _) ->
      ({ name; before; after; width } : Observation.t))
    |> List.filter ~f:(fun ({ name; before; after; _ } : Observation.t) ->
      String.equal name "PC"
      || List.mem spec.watch name ~equal:String.equal
      || not (String.equal before after))
  in
  { title = spec.title
  ; assembly
  ; word
  ; observations
  ; retirement = Value.string_of_value result
  ; setup
  ; arguments
  }
;;
