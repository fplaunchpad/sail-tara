type t =
  { word_width : int
  ; instructions : Instruction.t list
  }
[@@deriving yojson_of]
