open Libsail

module Instruction : sig
  (** An instruction, in the order of the union's constructors: its syntax, the fields of its word
      from the most significant bit, and the clauses that handle it, in source order. *)
  type t =
    { constructor : string
    ; operand_count : int
    ; syntax : string
    ; fields : Word_field.t list
    ; clauses : Clause.t list
    }
  [@@deriving yojson_of]
end

(** The decode clause that rejects the words of no instruction. In JSON, [name] is [function]. *)
module Fallback : sig
  type t =
    { name : string
    ; documented : bool
    }
  [@@deriving yojson_of]
end

type t =
  { word_width : int
  ; instructions : Instruction.t list
  ; outline : Outline.t
  ; fallback : Fallback.t
  }
[@@deriving yojson_of]

(** Reads the instruction set from the function [decode] and the mapping [assembly] of the
    instruction union to text. Every constructor of the union must have a clause in both. *)
val read : ast:Type_check.typed_ast -> env:Type_check.Env.t -> decode:string -> assembly:string -> t
