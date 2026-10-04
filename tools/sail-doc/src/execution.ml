open Core

let read ~env ~notation ~functions ~execute instruction =
  List.find_map functions ~f:(fun ({ name; pattern; body; _ } : Sail_ast.Function_clause.t) ->
    let%bind.Option () = Option.some_if (String.equal name execute) () in
    let%bind.Option constructor, patterns = Sail_ast.constructor_pat pattern in
    let patterns = List.map patterns ~f:(Sail_ast.Argument.of_pat env) in
    let%map.Option (_ : (string * Encoding.Argument.t) list) =
      Encoding.bindings instruction (constructor, patterns)
    in
    Notation.statements notation body)
;;
