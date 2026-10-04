(** A field of an instruction word: bits an encoding clause fixes (named by the type synonym that
    annotates them, if any), an operand it binds, or bits it ignores. In JSON, an object whose
    [kind] is [fixed], [operand] or [ignored]. *)

module Fixed : sig
  type t =
    { name : string option
    ; bits : string
    }
end

module Operand : sig
  type t =
    { name : string
    ; width : int
    }
end

module Ignored : sig
  type t = { width : int }
end

type t =
  | Fixed of Fixed.t
  | Operand of Operand.t
  | Ignored of Ignored.t
[@@deriving yojson_of]

val width : t -> int
