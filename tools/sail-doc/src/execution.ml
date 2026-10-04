open Core
open Libsail
open Extraction.Ast

let rec statements (E_aux (aux, _) as body : Type_check.tannot exp) =
  match aux with
  | E_lit (L_aux (L_unit, _)) -> []
  | E_block body -> List.concat_map body ~f:statement
  | _ -> statement body

and statement (E_aux (aux, _) as statement) =
  match aux with
  | E_let (_, bound, rest) | E_var (_, bound, rest) ->
    Sail_ast.source_span (Sail_ast.exp_location statement) (Sail_ast.exp_location bound)
    :: statements rest
  | _ -> [ Sail_ast.exp_location statement |> Sail_ast.source_text ]
;;

let read ~env ~functions ~execute instruction =
  List.find_map functions ~f:(fun ({ name; pattern; body; _ } : Sail_ast.Function_clause.t) ->
    let%bind.Option () = Option.some_if (String.equal name execute) () in
    let%bind.Option constructor, patterns = Sail_ast.constructor_pat pattern in
    let patterns = List.map patterns ~f:(Sail_ast.Argument.of_pat env) in
    let%map.Option (_ : (string * Encoding.Argument.t) list) =
      Encoding.bindings instruction (constructor, patterns)
    in
    statements body)
;;
