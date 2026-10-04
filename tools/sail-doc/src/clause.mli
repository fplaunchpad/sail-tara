open Core
open Libsail

(** Which side of its clause a constructor is on: the pattern of a function clause, or the left
    or right of a mapping clause. *)
module Selector : sig
  type t =
    | Pattern
    | Left
    | Right
end

(** A clause of the function or mapping [name] that takes a constructor apart: [pattern] is the
    constructor with the constants the Sail Asciidoctor plugin can match (enum members, binary
    and hexadecimal literals) and wildcards for the other arguments, which is how the plugin finds
    the clause. In JSON, [name] is [function]. *)
type t =
  { name : string
  ; selector : Selector.t
  ; pattern : string
  ; documented : bool
  }
[@@deriving yojson_of]

(** The clauses of every function and mapping that take one of [constructors] apart, by
    constructor, in source order. The plugin takes the first clause that a pattern matches, so a
    clause whose pattern also matches an earlier clause of the same function cannot be shown, and
    is an error. *)
val read
  :  ast:Type_check.typed_ast
  -> env:Type_check.Env.t
  -> constructors:String.Set.t
  -> t list String.Map.t
