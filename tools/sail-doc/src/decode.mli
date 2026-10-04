open Libsail

(** An instruction as a decode clause takes it apart: its constructor, the names of the operands it
    passes on (those that are fields, as they are named), and the fields of its word from the most
    significant bit. *)
type t =
  { constructor : string
  ; operands : string option list
  ; fields : Word_field.t list
  ; location : Parse_ast.l
  }

(** The instructions that the clauses of a decode function read, and its fallback: each clause but
    the last returns [Some(C(...))] for one instruction and matches fixed bits, names and
    wildcards; the last returns [None()] for any word. *)
val read
  :  Type_check.Env.t
  -> Sail_ast.Function_clause.t list
  -> t list * Sail_ast.Function_clause.t
