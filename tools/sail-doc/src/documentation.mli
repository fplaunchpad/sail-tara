open Libsail.Extraction.Ast

module Operand : sig
  type t =
    { name : string
    ; description : string
    }
  [@@deriving yojson_of]
end

module Note : sig
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

module Helper : sig
  type t =
    { title : string
    ; description : string
    }
end

val read : 'a def_annot -> t option
val helper : 'a def_annot -> Helper.t option
val validate : Encoding.t -> t -> unit
