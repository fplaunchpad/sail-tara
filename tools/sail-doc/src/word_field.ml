open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Fixed = struct
  type t =
    { name : string option
    ; bits : string
    }
  [@@deriving yojson_of]
end

module Operand = struct
  type t =
    { name : string
    ; width : int
    }
  [@@deriving yojson_of]
end

module Ignored = struct
  type t = { width : int } [@@deriving yojson_of]
end

type t =
  | Fixed of Fixed.t
  | Operand of Operand.t
  | Ignored of Ignored.t

let width = function
  | Fixed { bits; _ } -> String.length bits
  | Operand { width; _ } | Ignored { width } -> width
;;

let yojson_of_t = function
  | Fixed field -> Tagged.json ~kind:"fixed" (Fixed.yojson_of_t field)
  | Operand field -> Tagged.json ~kind:"operand" (Operand.yojson_of_t field)
  | Ignored field -> Tagged.json ~kind:"ignored" (Ignored.yojson_of_t field)
;;
