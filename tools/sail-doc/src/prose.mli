open Libsail

module Fragment : sig
  type t =
    { name : string
    ; description : string
    }
  [@@deriving yojson_of]
end

type t =
  { anchors : Fragment.t list
  ; registers : Fragment.t list
  ; constants : Fragment.t list
  }
[@@deriving yojson_of]

val anchors : Type_check.typed_ast -> (Fragment.t * Parse_ast.l) list
val read : Type_check.typed_ast -> t
