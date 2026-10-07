open Core

let read ~env ~notation ~functions ~execute instruction =
  let matching =
    List.filter_map
      functions
      ~f:(fun ({ name; pattern; body; guard; _ } : Sail_ast.Function_clause.t) ->
        let%bind.Option () = Option.some_if (String.equal name execute) () in
        let%bind.Option constructor, patterns = Sail_ast.constructor_pat pattern in
        let patterns = List.map patterns ~f:(Sail_ast.Argument.of_pat env) in
        let%map.Option bindings = Encoding.bindings instruction (constructor, patterns) in
        let bindings =
          List.map bindings ~f:(fun (name, argument) ->
            ( name
            , match argument with
              | Encoding.Argument.Operand value | Constant value -> value ))
          |> String.Map.of_alist_exn
        in
        let body = Operation.statements ~env ~notation ~bindings body in
        let guard = Option.map guard ~f:(Operation.expression ~env ~notation ~bindings) in
        guard, body)
  in
  let rec branches = function
    | [] -> []
    | (None, body) :: _ -> body
    | (Some condition, yes) :: rest -> [ Operation.Branch { condition; yes; no = branches rest } ]
  in
  Option.some_if (not (List.is_empty matching)) (branches matching)
;;
