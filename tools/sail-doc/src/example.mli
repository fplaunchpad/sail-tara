open Libsail

module Observation : sig
  type t =
    { name : string
    ; before : string
    ; after : string
    ; width : int option
    }
  [@@deriving yojson_of]
end

type t =
  { title : string
  ; assembly : string
  ; word : string
  ; observations : Observation.t list
  ; retirement : string
  ; setup : Documentation.State.t list
  ; arguments : string list
  }
[@@deriving yojson_of]

module Evaluator : sig
  type t

  val create : Interactive.State.istate -> t
end

val read
  :  Evaluator.t
  -> context:Documentation.Context.t
  -> encdec:string
  -> assembly:string
  -> Encoding.t
  -> Documentation.Example.t
  -> t
