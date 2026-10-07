open Core
open Libsail
open Extraction.Ast
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Value = struct
  type t =
    { name : string
    ; value : string
    }
  [@@deriving yojson]
end

module State = struct
  type t =
    { register : string
    ; index : int option [@default None]
    ; value : string
    }
  [@@deriving yojson]
end

module Example = struct
  type t =
    { title : string
    ; operands : Value.t list
    ; before : State.t list [@default []]
    ; arguments : string list [@default []]
    ; watch : string list [@default []]
    }
  [@@deriving yojson]
end

module Operand = struct
  type t =
    { name : string
    ; interpretation : string
    ; access : string
    ; description : string
    ; unit : string [@default ""]
    }
  [@@deriving yojson]
end

module Note = struct
  type t =
    { category : string
    ; text : string
    }
  [@@deriving yojson]
end

type t =
  { title : string
  ; operands : Operand.t list
  ; notes : Note.t list [@default []]
  ; related : string list [@default []]
  ; examples : Example.t list
  ; id : string option [@default None]
  }
[@@deriving yojson]

module Observed = struct
  type t =
    { register : string
    ; label : string
    }
  [@@deriving yojson]
end

module Context = struct
  type t =
    { runner : string
    ; arguments : string list
    ; initial : State.t list
    ; observed : Observed.t list
    ; complete : bool
    }
  [@@deriving yojson]
end

module Helper = struct
  type t =
    { title : string
    ; description : string [@default ""]
    }
  [@@deriving yojson]
end

let read_attribute name decode annot =
  match
    Ast_util.get_def_attributes annot
    |> List.filter_map ~f:(fun (location, key, data) ->
      Option.some_if (String.equal key name) (location, data))
  with
  | [] -> None
  | [ (location, Some data) ] ->
    let json =
      Ast_util.json_of_attribute_data data |> Yojson.Basic.to_string |> Yojson.Safe.from_string
    in
    (try Some (decode json) with
     | Ppx_yojson_conv_lib.Yojson_conv.Of_yojson_error (error, _) ->
       Sail_ast.fail_at location [%string "invalid %{name}: %{Exn.to_string error}"])
  | (location, _) :: _ ->
    Sail_ast.fail_at location [%string "%{name} must occur once with an object"]
;;

let paragraph text =
  String.split_lines text
  |> List.map ~f:(fun line -> String.strip line)
  |> String.concat ~sep:" "
  |> String.strip
;;

let read annot =
  let%map.Option doc = read_attribute "instruction_doc" t_of_yojson annot in
  { doc with
    title = paragraph doc.title
  ; operands =
      List.map doc.operands ~f:(fun operand ->
        { operand with Operand.description = paragraph operand.description })
  ; notes = List.map doc.notes ~f:(fun note -> { note with Note.text = paragraph note.text })
  }
;;

let helper annot = read_attribute "helper_doc" Helper.t_of_yojson annot

let identifier value =
  (not (String.is_empty value))
  && (Char.is_alpha value.[0] || Char.equal value.[0] '_')
  && String.for_all value ~f:(fun char -> Char.is_alphanum char || Char.equal char '_')
;;

let validate_literal location value =
  let digits prefix valid =
    String.is_prefix value ~prefix
    && String.length value > String.length prefix
    && String.drop_prefix value (String.length prefix) |> String.for_all ~f:valid
  in
  let decimal = String.chop_prefix_if_exists value ~prefix:"-" in
  if
    not
      (List.mem [ "true"; "false" ] value ~equal:String.equal
       || digits "0b" (fun char -> Char.equal char '0' || Char.equal char '1')
       || digits "0x" Char.is_hex_digit
       || ((not (String.is_empty decimal)) && String.for_all decimal ~f:Char.is_digit))
  then Sail_ast.fail_at location [%string "example values must be literals, got %{value}"]
;;

let validate_state location ({ register; index; value } : State.t) =
  if
    (not (identifier register)) || Option.value_map index ~default:false ~f:(fun index -> index < 0)
  then Sail_ast.fail_at location "example state needs a register name and a nonnegative index";
  validate_literal location value
;;

let context (ast : Type_check.typed_ast) execute =
  List.find_map ast.defs ~f:(function
    | DEF_aux (DEF_val (VS_aux (VS_val_spec (_, id, _), _)), annot)
      when String.equal (Sail_ast.id_string id) execute ->
      let%map.Option context = read_attribute "doc_examples" Context.t_of_yojson annot in
      if (not (identifier context.runner)) || List.is_empty context.observed
      then Sail_ast.fail_at annot.loc "doc_examples needs a runner and observed state";
      let registers =
        List.filter_map ast.defs ~f:(function
          | DEF_aux (DEF_register (DEC_aux (DEC_reg (_, id, _), _)), _) ->
            Some (Sail_ast.id_string id)
          | _ -> None)
      in
      let observed =
        List.map context.observed ~f:(fun ({ register; label } : Observed.t) ->
          if (not (List.mem registers register ~equal:String.equal)) || String.is_empty label
          then
            Sail_ast.fail_at annot.loc "doc_examples observations need known registers and labels";
          register)
      in
      if List.contains_dup observed ~compare:String.compare
      then Sail_ast.fail_at annot.loc "duplicate doc_examples observation";
      List.iter context.initial ~f:(validate_state annot.loc);
      List.iter context.arguments ~f:(validate_literal annot.loc);
      context
    | _ -> None)
;;

let validate (encoding : Encoding.t) (doc : t) =
  let fields =
    List.filter_map encoding.fields ~f:(function
      | Word_field.Operand { name; _ } -> Some name
      | Fixed _ | Ignored _ -> None)
    |> String.Set.of_list
  in
  let names = List.map doc.operands ~f:(fun ({ name; _ } : Operand.t) -> name) in
  if
    (not (Set.equal fields (String.Set.of_list names)))
    || List.contains_dup names ~compare:String.compare
  then
    Sail_ast.fail_at
      encoding.location
      "instruction_doc operands must name each encoding operand once";
  if String.is_empty doc.title || List.is_empty doc.examples
  then
    Sail_ast.fail_at encoding.location "instruction_doc requires a title and at least one example";
  List.iter doc.operands ~f:(fun ({ interpretation; access; description; _ } : Operand.t) ->
    if
      (not (List.mem [ "register"; "signed"; "unsigned" ] interpretation ~equal:String.equal))
      || (not (List.mem [ "read"; "write"; "read_write"; "value" ] access ~equal:String.equal))
      || String.is_empty description
    then Sail_ast.fail_at encoding.location "invalid operand interpretation, access, or description");
  List.iter doc.notes ~f:(fun ({ category; text } : Note.t) ->
    if
      (not (List.mem [ "usage"; "architecture"; "assumption" ] category ~equal:String.equal))
      || String.is_empty text
    then
      Sail_ast.fail_at
        encoding.location
        "notes require usage, architecture, or assumption and nonempty text");
  List.iter doc.examples ~f:(fun ({ title; operands; before; arguments; watch } : Example.t) ->
    if String.is_empty title || List.contains_dup watch ~compare:String.compare
    then Sail_ast.fail_at encoding.location "examples need a title and unique watch labels";
    List.iter operands ~f:(fun ({ value; _ } : Value.t) -> validate_literal encoding.location value);
    List.iter before ~f:(validate_state encoding.location);
    List.iter arguments ~f:(validate_literal encoding.location))
;;
