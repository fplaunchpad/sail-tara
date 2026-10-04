(** A field of an instruction word: an operand's name, [opcode], or [padding] for bits that decoding
    ignores. *)
type t =
  { name : string
  ; width : int
  }
[@@deriving yojson_of]

val opcode : string
val padding : string
