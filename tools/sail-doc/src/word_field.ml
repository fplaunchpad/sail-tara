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

let tagged kind = function
  | `Assoc fields -> `Assoc (("kind", `String kind) :: fields)
  | json -> json
;;

let yojson_of_t = function
  | Fixed field -> tagged "fixed" (Fixed.yojson_of_t field)
  | Operand field -> tagged "operand" (Operand.yojson_of_t field)
  | Ignored field -> tagged "ignored" (Ignored.yojson_of_t field)
;;
