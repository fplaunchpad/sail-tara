open Core
open Libsail

(** How a clause is found among its function's or mapping's: by the constructor its pattern takes
    apart, by the constructor its body builds (as a decode clause's does), or by the constructor
    on the left or right of a mapping clause. *)
module Selector : sig
  type t =
    | Pattern
    | Body
    | Left
    | Right
end

(** A clause of the function or mapping [name] for one instruction. In JSON, [name] is
    [function]. *)
type t =
  { name : string
  ; selector : Selector.t
  ; documented : bool
  }
[@@deriving yojson_of]

(** The clauses of every function and mapping that take an instruction apart or build one, by
    constructor, in source order. *)
val read : ast:Type_check.typed_ast -> constructors:String.Set.t -> t list String.Map.t
