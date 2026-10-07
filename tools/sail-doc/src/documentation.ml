open Core
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Operand = struct
  type t =
    { name : string
    ; description : string
    }
  [@@deriving yojson_of]
end

module Note = struct
  type t =
    { category : string
    ; text : string
    }
  [@@deriving yojson_of]
end

type t =
  { title : string
  ; operands : Operand.t list
  ; notes : Note.t list
  ; related : string list
  ; id : string option
  }
[@@deriving yojson_of]

module Helper = struct
  type t =
    { title : string
    ; description : string
    }
end

let read annot =
  let%bind.Option doc = Doc_comment.read annot in
  let%map.Option title = doc.brief in
  { title
  ; operands =
      List.map doc.parameters ~f:(fun { name; text } -> ({ name; description = text } : Operand.t))
  ; notes = List.map doc.notes ~f:(fun { category; text } -> ({ category; text } : Note.t))
  ; related = doc.related
  ; id = doc.id
  }
;;

let helper annot =
  let%bind.Option doc = Doc_comment.read annot in
  let%map.Option title = doc.brief in
  ({ title; description = doc.body } : Helper.t)
;;

let validate (encoding : Encoding.t) (doc : t) =
  let fields =
    List.filter_map encoding.fields ~f:(function
      | Word_field.Operand { name; _ } -> Some name
      | Fixed _ | Ignored _ -> None)
    |> String.Set.of_list
  in
  let names = List.map doc.operands ~f:(fun ({ name; _ } : Operand.t) -> name) in
  if not (Set.equal fields (String.Set.of_list names))
  then Sail_ast.fail_at encoding.location "@param must name each encoding operand once"
;;
