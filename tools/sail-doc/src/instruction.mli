module Field : sig
  type t =
    { name : string
    ; width : int
    }
  [@@deriving yojson_of]
end

type t =
  { constructor : string
  ; opcode_bits : string
  ; syntax : string
  ; fields : Field.t list
  }
[@@deriving yojson_of]
