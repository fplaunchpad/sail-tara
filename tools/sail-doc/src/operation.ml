open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Expression = struct
  type t =
    | Value of
        { text : string
        ; width : int option
        }
    | Call of
        { name : string
        ; arguments : t list
        ; width : int option
        ; notation : string option
        }
    | Binary of
        { operator : string
        ; left : t
        ; right : t
        ; width : int option
        }
    | Slice of
        { value : t
        ; high : t
        ; low : t option
        ; width : int option
        }
    | Choice of
        { condition : t
        ; yes : t
        ; no : t
        ; width : int option
        }
  [@@deriving yojson_of]

  let yojson_of_t value = yojson_of_t value |> Tagged.tree
end

type t =
  | Evaluate of { value : Expression.t }
  | Assign of
      { target : Expression.t
      ; value : Expression.t
      }
  | Bind of
      { name : string
      ; value : Expression.t
      ; body : t list
      }
  | Branch of
      { condition : Expression.t
      ; yes : t list
      ; no : t list
      }
[@@deriving yojson_of]

let yojson_of_t value = yojson_of_t value |> Tagged.tree
let width env expression = Type_check.typ_of expression |> Sail_ast.bits_width env
let binding bindings name = Map.find bindings name |> Option.value ~default:name

let rec expression
          ~env
          ~notation
          ~bindings
          (E_aux (aux, (location, _)) as full : Type_check.tannot exp)
  : Expression.t
  =
  let read = expression ~env ~notation ~bindings in
  let width = width env full in
  match aux with
  | E_lit literal -> Value { text = Ast_util.string_of_lit literal; width }
  | E_id id ->
    let name = Sail_ast.id_string id |> binding bindings in
    Value { text = Notation.find notation name |> Option.value ~default:name; width }
  | E_typ (_, nested) -> read nested
  | E_block [ nested ] -> read nested
  | E_app (id, arguments) ->
    let name = Sail_ast.id_string id in
    (match arguments with
     | [ left; right ]
       when (not (String.equal name "concat_str"))
            && Option.is_some (Notation.written_operator location left right) ->
       Binary
         { operator = Option.value_exn (Notation.written_operator location left right)
         ; left = read left
         ; right = read right
         ; width
         }
     | _ ->
       Call
         { name
         ; arguments = List.map arguments ~f:read
         ; width
         ; notation = Notation.find notation name
         })
  | E_if (condition, yes, no) ->
    Choice { condition = read condition; yes = read yes; no = read no; width }
  | _ ->
    Sail_ast.fail_at
      location
      "documentation cannot describe this expression; add structured operation support"
;;

let rec target ~env ~notation ~bindings (LE_aux (aux, (location, annot)) : Type_check.tannot lexp)
  : Expression.t
  =
  let read = expression ~env ~notation ~bindings in
  let width = Sail_ast.bits_width env (Type_check.typ_of_tannot annot) in
  match aux with
  | LE_id id | LE_typ (_, id) ->
    let name = Sail_ast.id_string id |> binding bindings in
    Value { text = Notation.find notation name |> Option.value ~default:name; width }
  | LE_vector (value, high) ->
    Slice { value = target ~env ~notation ~bindings value; high = read high; low = None; width }
  | LE_vector_range (value, high, low) ->
    Slice
      { value = target ~env ~notation ~bindings value
      ; high = read high
      ; low = Some (read low)
      ; width
      }
  | _ -> Sail_ast.fail_at location "documentation cannot describe this assignment target"
;;

let rec statements ~env ~notation ~bindings (E_aux (aux, _) as body : Type_check.tannot exp) =
  let read = expression ~env ~notation ~bindings in
  let nested = statements ~env ~notation ~bindings in
  match aux with
  | E_lit (L_aux (L_unit, _)) | E_block [] -> []
  | E_block body -> List.concat_map body ~f:nested
  | E_assign (destination, value) ->
    [ Assign { target = target ~env ~notation ~bindings destination; value = read value } ]
  | E_let (pattern, value, body) ->
    let name =
      match Sail_ast.unwrap_pat pattern with
      | P_aux (P_id id, _) -> Sail_ast.id_string id
      | _ ->
        Sail_ast.fail_at
          (Sail_ast.pat_location pattern)
          "documentation requires a named local binding"
    in
    let rec available candidate =
      if
        List.mem (Map.data bindings) candidate ~equal:String.equal
        || Option.is_some (Notation.find notation candidate)
      then available ("local_" ^ candidate)
      else candidate
    in
    let display = available name in
    let scope = Map.set bindings ~key:name ~data:display in
    [ Bind
        { name = display
        ; value = read value
        ; body = statements ~env ~notation ~bindings:scope body
        }
    ]
  | E_if (condition, yes, no) ->
    [ Branch { condition = read condition; yes = nested yes; no = nested no } ]
  | _ -> [ Evaluate { value = read body } ]
;;

let rec expression_calls (value : Expression.t) =
  match value with
  | Value _ -> []
  | Call { name; arguments; _ } -> name :: List.concat_map arguments ~f:expression_calls
  | Binary { left; right; _ } -> expression_calls left @ expression_calls right
  | Slice { value; high; low; _ } ->
    expression_calls value
    @ expression_calls high
    @ Option.value_map low ~default:[] ~f:expression_calls
  | Choice { condition; yes; no; _ } ->
    expression_calls condition @ expression_calls yes @ expression_calls no
;;

let rec calls = function
  | Evaluate { value } -> expression_calls value
  | Assign { target; value } -> expression_calls target @ expression_calls value
  | Bind { value; body; _ } -> expression_calls value @ List.concat_map body ~f:calls
  | Branch { condition; yes; no } ->
    expression_calls condition @ List.concat_map (yes @ no) ~f:calls
;;
