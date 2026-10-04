open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type t =
  { word_width : int
  ; instructions : Instruction.t list
  }
[@@deriving yojson_of]
