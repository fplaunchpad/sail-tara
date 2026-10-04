open Libsail

(** An instruction as a decode clause takes it apart: its constructor and operand names, its opcode,
    and the fields of its word from the most significant bit, starting with the opcode. *)
type t =
  { constructor : string
  ; operands : string list
  ; opcode : string
  ; fields : Word_field.t list
  ; location : Parse_ast.l
  }

(** The instructions that the clauses of decode read. Each clause must match its opcode's bits
    followed by names and wildcards, and the last must be the only one that returns [None()]. *)
val read : Type_check.Env.t -> Sail_ast.Function_clause.t list -> t list
