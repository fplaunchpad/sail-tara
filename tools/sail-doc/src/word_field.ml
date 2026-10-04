open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type t =
  { name : string
  ; width : int
  }
[@@deriving yojson_of]

let opcode = "opcode"
let padding = "padding"
