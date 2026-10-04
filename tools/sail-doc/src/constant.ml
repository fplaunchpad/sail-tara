open Core
open Libsail
open Extraction.Ast
open Type_check

type t =
  { source_env : Type_check.Env.t
  ; env : Type_check.Env.t
  ; effects : Effects.side_effect_info
  ; state : Interpreter.state
  }

let create (istate : Interactive.State.istate) =
  Or_error.try_with
  @@ fun () ->
  let rewrites = Rewrites.instantiate_rewrites Rewrites.rewrites_interpreter in
  let _ctx, ast, _rewritten_effects, env =
    Rewrites.rewrite istate.ctx istate.effect_info istate.env rewrites istate.ast
  in
  (* The rewrite copies bidirectional mapping effects to both directions. Re-infer over the lowered AST so a
     partial reverse clause does not make a total forward function appear impure. *)
  let effects = Effects.infer_side_effects false ast in
  let state =
    Interpreter.initial_state
      ~registers:false
      ~undef_registers:false
      ast
      env
      Constant_fold.safe_primops
  in
  ({ source_env = istate.env; env; effects; state } : t)
;;

let rec expression (context : t) (pattern : tannot mpat) : tannot exp =
  let location, annotation =
    match pattern with
    | MP_aux (_, annot) -> annot
  in
  let create aux : tannot exp = E_aux (aux, (location, annotation)) in
  match pattern with
  | MP_aux (MP_lit literal, _) -> create (E_lit literal)
  | MP_aux (MP_app (id, arguments), _) ->
    let target =
      if Type_check.Env.is_mapping id context.source_env
      then Ast_util.append_id id "_forwards"
      else id
    in
    ignore (Type_check.Env.lookup_id target context.env);
    if not (Effects.function_is_pure target context.effects)
    then
      raise
        (Reporting.err_general
           location
           [%string "documentation mapping call %{Ast_util.string_of_id target} is not pure"]);
    create (E_app (target, List.map arguments ~f:(expression context)))
  | MP_aux (MP_string_append parts, _) ->
    List.fold_right
      parts
      ~init:(create (E_lit (L_aux (L_string "", location))))
      ~f:(fun part rest ->
        let left = expression context part in
        let rest_location, rest_annotation =
          match rest with
          | E_aux (_, annot) -> annot
        in
        E_aux (E_app (Ast_util.mk_id "concat_str", [ left; rest ]), (rest_location, rest_annotation)))
  | MP_aux (MP_typ (nested, _), _) -> expression context nested
  | MP_aux (MP_id id, _) when String.equal (Ast_util.string_of_id id) "_" ->
    raise (Reporting.err_general location "documentation mapping wildcard is not closed")
  | MP_aux (MP_id id, _) ->
    raise
      (Reporting.err_general
         location
         [%string "documentation mapping value %{Ast_util.string_of_id id} is not closed"])
  | _ -> raise (Reporting.err_general location "unsupported closed mapping expression")
;;

let rec run_frame location frame =
  match frame with
  | Interpreter.Done (_, V_string text) -> text
  | Interpreter.Done (_, _) ->
    raise (Reporting.err_general location "closed documentation mapping did not return a string")
  | Interpreter.Step _ | Interpreter.Break _ -> run_frame location (Interpreter.eval_frame frame)
  | Interpreter.Fail (_, _, _, _, message) -> raise (Reporting.err_general location message)
  | Interpreter.Effect_request _ ->
    raise (Reporting.err_general location "closed documentation mapping attempted a side effect")
;;

let eval (context : t) (pattern : tannot mpat) =
  Or_error.try_with
  @@ fun () ->
  let location = Sail_ast.mpat_location pattern in
  let expression = expression context pattern in
  let frame =
    Interpreter.Step
      (lazy "TARA documentation mapping", context.state, Interpreter.Monad.pure expression, [])
  in
  run_frame location frame
;;
