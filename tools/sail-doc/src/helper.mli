open Libsail

module Rule : sig
  type t =
    { direction : string
    ; input : string
    ; output : Operation.Expression.t
    ; guard : Operation.Expression.t option
    }
  [@@deriving yojson_of]
end

type t =
  { name : string
  ; title : string
  ; signature : string
  ; description : string
  ; operation : Operation.t list
  ; rules : Rule.t list
  ; dependencies : string list
  ; source_kind : string
  ; documented : bool
  ; source : string
  }
[@@deriving yojson_of]

val read
  :  ast:Type_check.typed_ast
  -> env:Type_check.env
  -> notation:Notation.t
  -> roots:string list
  -> calls:string list
  -> t list
