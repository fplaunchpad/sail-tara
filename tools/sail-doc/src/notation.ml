open Core
open Libsail
open Extraction.Ast

type t = string String.Map.t

(* Sail's library, written as a reference card writes it. *)
let library =
  [ "bitzero", "0"
  ; "bitone", "1"
  ; "signed", "sext({0})"
  ; "unsigned", "{0}"
  ; "sign_extend", "sext({1})"
  ; "zero_extend", "zext({1})"
  ; "sail_sign_extend", "sext({0})"
  ; "sail_zero_extend", "zext({0})"
  ; "not_vec", "~{0}"
  ; "sail_shiftleft", "{0} << {1}"
  ; "sail_shiftright", "{0} >> {1}"
  ; "vector_subrange", "{0}({1}:{2})"
  ; "subrange_bits", "{0}({1}:{2})"
  ; "vector_access", "{0}({1})"
  ; "bitvector_access", "{0}({1})"
  ]
;;

let read (ast : Type_check.typed_ast) =
  let named =
    List.filter_map ast.defs ~f:(fun (DEF_aux (def, annot)) ->
      let%bind.Option name =
        match def with
        | DEF_fundef (FD_aux (FD_function (_, _, FCL_aux (FCL_funcl (id, _), _) :: _), _))
        | DEF_val (VS_aux (VS_val_spec (_, id, _), _))
        | DEF_register (DEC_aux (DEC_reg (_, id, _), _)) -> Some (Sail_ast.id_string id)
        | DEF_let (pattern, _) ->
          (match Sail_ast.unwrap_pat pattern with
           | P_aux (P_id id, _) -> Some (Sail_ast.id_string id)
           | _ -> None)
        | _ -> None
      in
      match Ast_util.get_def_attribute "notation" annot with
      | Some (_, Some (AD_aux (AD_string template, _))) -> Some (name, template)
      | Some (location, _) ->
        Sail_ast.fail_at location "a notation is a string, such as $[notation \"R[{0}]\"]"
      | None -> None)
  in
  String.Map.of_alist_reduce (library @ named) ~f:(fun _ model -> model)
;;

(* How tightly an infix operator binds, as in C; any other binds loosest. *)
let precedence = function
  | "*" | "/" | "%" -> 7
  | "+" | "-" | "++" -> 6
  | "<<" | ">>" -> 5
  | "<" | "<=" | ">" | ">=" -> 4
  | "==" | "!=" -> 3
  | "&" -> 2
  | "^" -> 1
  | _ -> 0
;;

module Printed = struct
  (* Text, and the operator at its top if it is an infix application. *)
  type t =
    { text : string
    ; operator : string option
    }

  let atom text = { text; operator = None }

  (* An operand of [operator], in parentheses if it binds less tightly, or as tightly on the
     right. *)
  let operand ~operator ~right { text; operator = inner } =
    match inner with
    | Some inner
      when precedence inner < precedence operator
           || (right && precedence inner = precedence operator) -> [%string "(%{text})"]
    | Some _ | None -> text
  ;;

  let infix operator left right =
    let left = operand ~operator ~right:false left in
    let right = operand ~operator ~right:true right in
    { text = [%string "%{left} %{operator} %{right}"]; operator = Some operator }
  ;;
end

(* [template] with the arguments in place. An infix argument goes in parentheses unless brackets,
   commas or spaces set it apart, as in [R[{0}]] but not in [{0}(7:0)] or [~{0}]. *)
let fill template (arguments : Printed.t list) =
  List.foldi arguments ~init:template ~f:(fun index template ({ text; operator } : Printed.t) ->
    let placeholder = [%string "{%{index#Int}}"] in
    let apart =
      match String.substr_index template ~pattern:placeholder with
      | None -> true
      | Some start ->
        let finish = start + String.length placeholder in
        (start = 0 || String.mem "[(, " template.[start - 1])
        && (finish = String.length template || String.mem "]), " template.[finish])
    in
    let text = if Option.is_some operator && not apart then [%string "(%{text})"] else text in
    String.substr_replace_all template ~pattern:placeholder ~with_:text)
;;

(* The operator of a template [{0} OP {1}]. *)
let template_operator template =
  match String.split template ~on:' ' with
  | [ "{0}"; operator; "{1}" ] -> Some operator
  | _ -> None
;;

(* The operator between two operands, if the application is written infix. *)
let written_operator location left right =
  let left = Sail_ast.exp_location left in
  let%bind.Option () = Option.some_if (Sail_ast.same_start location left) () in
  let%bind.Option between = Sail_ast.source_between left (Sail_ast.exp_location right) in
  match String.strip between with
  | "@" -> Some "++"
  | operator
    when (not (String.is_empty operator)) && not (String.exists operator ~f:(String.mem "[](){},;"))
    -> Some operator
  | _ -> None
;;

let is_zeros (E_aux (aux, _) : Type_check.tannot exp) =
  match aux with
  | E_lit (L_aux ((L_bin _ | L_hex _), _) as value) ->
    String.drop_prefix (Ast_util.string_of_lit value) 2 |> String.for_all ~f:(Char.equal '0')
  | _ -> false
;;

let literal (L_aux (literal, _) as full : lit) =
  match literal with
  | L_bin _ | L_hex _ ->
    Ast_util.string_of_lit full |> Big_int_Z.big_int_of_string |> Big_int_Z.string_of_big_int
  | _ -> Ast_util.string_of_lit full
;;

(* The source of a construct the notation does not cover, on one line. *)
let source location =
  Sail_ast.source_text location
  |> String.split_on_chars ~on:[ ' '; '\n'; '\t' ]
  |> List.filter ~f:(Fn.non String.is_empty)
  |> String.concat ~sep:" "
;;

let rec expression notation (E_aux (aux, (location, _)) : Type_check.tannot exp) : Printed.t =
  let text exp = (expression notation exp).text in
  match aux with
  | E_lit value -> Printed.atom (literal value)
  | E_id id ->
    let name = Sail_ast.id_string id in
    Printed.atom (Map.find notation name |> Option.value ~default:name)
  | E_typ (_, nested) -> expression notation nested
  | E_app (_, [ left; right ]) when Option.is_some (written_operator location left right) ->
    (match written_operator location left right with
     | Some "++" when is_zeros left -> Printed.atom [%string "zext(%{text right})"]
     | Some operator ->
       Printed.infix operator (expression notation left) (expression notation right)
     | None -> Printed.atom (source location))
  | E_app (id, [ E_aux (E_lit width, _); value; E_aux (E_lit low, _) ])
    when String.equal (Sail_ast.id_string id) "get_slice_int" ->
    let low = Int.of_string (literal low) in
    let high = Int.of_string (literal width) + low - 1 in
    Printed.atom (fill [%string "{0}(%{high#Int}:%{low#Int})"] [ expression notation value ])
  | E_app (id, arguments) ->
    let name = Sail_ast.id_string id in
    let printed = List.map arguments ~f:(expression notation) in
    (match Map.find notation name, printed with
     | Some template, [ left; right ] when Option.is_some (template_operator template) ->
       Printed.infix (Option.value_exn (template_operator template)) left right
     | Some "{0}", [ argument ] -> argument
     | Some template, _ -> Printed.atom (fill template printed)
     | None, _ ->
       let arguments = List.map printed ~f:(fun { text; _ } -> text) |> String.concat ~sep:", " in
       Printed.atom [%string "%{name}(%{arguments})"])
  | E_if (condition, then_, else_) ->
    Printed.atom [%string "%{text condition} ? %{text then_} : %{text else_}"]
  | E_block [ single ] -> expression notation single
  | _ -> Printed.atom (source location)
;;

let rec statements notation (E_aux (aux, _) as body : Type_check.tannot exp) =
  let text exp = (expression notation exp).text in
  let block exp = statements notation exp |> String.concat ~sep:"; " in
  match aux with
  | E_lit (L_aux (L_unit, _)) | E_block [] -> []
  | E_block body -> List.concat_map body ~f:(statements notation)
  | E_let (pattern, bound, rest) ->
    let name =
      match Sail_ast.unwrap_pat pattern with
      | P_aux (P_id id, _) -> Sail_ast.id_string id
      | _ -> source (Sail_ast.pat_location pattern)
    in
    [%string "%{name} = %{text bound}"] :: statements notation rest
  | E_assign (LE_aux ((LE_id id | LE_typ (_, id)), _), value) ->
    let name = Sail_ast.id_string id in
    let name = Map.find notation name |> Option.value ~default:name in
    [ [%string "%{name} = %{text value}"] ]
  | E_if (condition, then_, else_) ->
    (match statements notation else_ with
     | [] -> [ [%string "if (%{text condition}) %{block then_}"] ]
     | _ -> [ [%string "if (%{text condition}) %{block then_} else %{block else_}"] ])
  | _ -> [ text body ]
;;
