open Libsail

module Instruction : sig
  (** An instruction, a clause of the encoding mapping: its constructor, its assembly syntax, the
      fields of its word from the most significant bit, the source of its guard if it has one,
      and the statements that carry it out. *)
  type t =
    { constructor : string
    ; syntax : string
    ; fields : Word_field.t list
    ; condition : string option
    ; execution : string list
    }
  [@@deriving yojson_of]
end

type t =
  { word_width : int
  ; instructions : Instruction.t list
  ; outline : Outline.t
  }
[@@deriving yojson_of]

(** Reads the instruction set from the mapping [encdec] of the instruction union to words, the
    mapping [assembly] of instructions to text and the function [execute]. Every constructor of
    the union must have an [encdec] clause, and every instruction must have [assembly] and
    [execute] clauses. *)
val read
  :  ast:Type_check.typed_ast
  -> env:Type_check.Env.t
  -> encdec:string
  -> assembly:string
  -> execute:string
  -> t
