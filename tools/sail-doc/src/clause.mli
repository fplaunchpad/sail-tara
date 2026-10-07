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

(** A clause that takes a constructor apart, with its exact source and documentation comment.
    [pattern] retains constants and wildcards for the other arguments. In JSON, [name] is
    [function]. *)
type t =
  { name : string
  ; selector : Selector.t
  ; pattern : string
  ; documented : bool
  ; source : string
  ; description : string
  }
[@@deriving yojson_of]

(** Clauses grouped by constructor in source order. A clause hidden by an unguarded earlier
    clause is rejected; guarded alternatives retain their own sources. *)
val read
  :  ast:Type_check.typed_ast
  -> env:Type_check.Env.t
  -> constructors:String.Set.t
  -> t list String.Map.t
