open Libsail
open Extraction.Ast

module Value : sig
  type t =
    { name : string
    ; value : string
    }
  [@@deriving yojson]
end

module State : sig
  type t =
    { register : string
    ; index : int option [@default None]
    ; value : string
    }
  [@@deriving yojson]
end

module Example : sig
  type t =
    { title : string
    ; operands : Value.t list
    ; before : State.t list [@default []]
    ; arguments : string list [@default []]
    ; watch : string list [@default []]
    }
  [@@deriving yojson]
end

module Operand : sig
  type t =
    { name : string
    ; interpretation : string
    ; access : string
    ; description : string
    ; unit : string [@default ""]
    }
  [@@deriving yojson]
end

module Note : sig
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

module Observed : sig
  type t =
    { register : string
    ; label : string
    }
  [@@deriving yojson]
end

module Context : sig
  type t =
    { runner : string
    ; arguments : string list
    ; initial : State.t list
    ; observed : Observed.t list
    ; complete : bool
    }
  [@@deriving yojson]
end

module Helper : sig
  type t =
    { title : string
    ; description : string [@default ""]
    }
  [@@deriving yojson]
end

val read : 'a def_annot -> t option
val helper : 'a def_annot -> Helper.t option
val context : Type_check.typed_ast -> string -> Context.t option
val validate : Encoding.t -> t -> unit
