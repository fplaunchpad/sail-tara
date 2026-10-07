open Libsail

module Operand : sig
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

module Spec : sig
  type t =
    { title : string
    ; operands : Operand.t list
    ; before : State.t list [@default []]
    ; arguments : string list [@default []]
    ; watch : string list [@default []]
    }
  [@@deriving yojson]
end

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
    }
  [@@deriving yojson]
end

module Input : sig
  type t =
    { syntax : string
    ; examples : Spec.t list
    }
  [@@deriving yojson]
end

module Config : sig
  type t =
    { context : Context.t
    ; instructions : Input.t list
    }
  [@@deriving yojson]

  val read : Type_check.typed_ast -> string -> t
end

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
  ; setup : State.t list
  ; arguments : string list
  }
[@@deriving yojson_of]

module Evaluator : sig
  type t

  val create : Interactive.State.istate -> t
end

val read
  :  Evaluator.t
  -> context:Context.t
  -> encdec:string
  -> assembly:string
  -> Encoding.t
  -> Spec.t
  -> t
