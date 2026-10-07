open Libsail.Extraction.Ast

module Entry : sig
  type t =
    { name : string
    ; text : string
    }
end

module Note : sig
  type t =
    { category : string
    ; text : string
    }
end

type t =
  { body : string
  ; brief : string option
  ; parameters : Entry.t list
  ; notes : Note.t list
  ; related : string list
  ; notation : string option
  ; id : string option
  ; anchors : Entry.t list
  }

val identifier : string -> bool
val read : 'a def_annot -> t option
val body : 'a def_annot -> string
