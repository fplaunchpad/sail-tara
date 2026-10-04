open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Field = struct
  type t =
    { name : string
    ; width : int
    }
  [@@deriving yojson_of]
end

type t =
  { constructor : string
  ; source_file : string
  ; operand_count : int
  ; opcode_bits : string
  ; syntax : string
  ; fields : Field.t list
  }
[@@deriving yojson_of]
