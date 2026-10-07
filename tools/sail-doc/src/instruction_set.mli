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
    ; execution : Operation.t list
    ; documentation : Documentation.t option
    ; description : string
    ; examples : Example.t list
    }
  [@@deriving yojson_of]
end

type t =
  { schema_version : int
  ; word_width : int
  ; instructions : Instruction.t list
  ; outline : Outline.t
  ; helpers : Helper.t list
  ; retirement : Operation.t list
  ; complete : bool
  ; context : Documentation.Context.t option
  }
[@@deriving yojson_of]

(** Reads the instruction set from the mapping [encdec] of the instruction union to words, the
    mapping [assembly] of instructions to text and the function [execute]. Every constructor of
    the union must have an [encdec] clause, and every instruction must have [assembly] and
    [execute] clauses. *)
val read : state:Interactive.State.istate -> encdec:string -> assembly:string -> execute:string -> t
