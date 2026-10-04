open Libsail

module Item : sig
  type t =
    | Anchor of string
    | Instruction of string
end

(** The documented anchors and the instructions of the files that define instructions, in source
    order. In JSON, objects whose [kind] is [anchor] or [instruction], with a [name]. *)
type t = Item.t list [@@deriving yojson_of]

(** The outline of the files that define [constructors], given with their locations. *)
val read : ast:Type_check.typed_ast -> constructors:(string * Parse_ast.l) list -> t
