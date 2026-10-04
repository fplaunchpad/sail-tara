open Libsail

module Instruction : sig
  (** [operand_count] is the number of the constructor's arguments, and [fields] lay out its word
      from the most significant bit. *)
  type t =
    { constructor : string
    ; source_file : string
    ; operand_count : int
    ; opcode_bits : string
    ; syntax : string
    ; fields : Word_field.t list
    }
  [@@deriving yojson_of]
end

(** The instructions of a model, by opcode, and the width of their words. *)
type t =
  { word_width : int
  ; instructions : Instruction.t list
  }
[@@deriving yojson_of]

(** Reads the instruction set from the function [decode] and the mapping [assembly] of the
    instruction union to text. Every constructor of the union must have a clause in both. *)
val read : ast:Type_check.typed_ast -> env:Type_check.Env.t -> decode:string -> assembly:string -> t
