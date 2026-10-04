open Libsail

module Item : sig
  (** An instruction constructor and the clauses that take it apart, in source order. *)
  module Constructor : sig
    type t =
      { name : string
      ; clauses : Clause.t list
      }
  end

  type t =
    | Anchor of string
    | Constructor of Constructor.t
end

(** The documented anchors and the instruction constructors of the files that define
    constructors, in source order. In JSON, objects whose [kind] is [anchor] or [constructor]. *)
type t = Item.t list [@@deriving yojson_of]

(** The outline of the files that define [constructors], given with their locations. *)
val read : ast:Type_check.typed_ast -> constructors:(Item.Constructor.t * Parse_ast.l) list -> t
