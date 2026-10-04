open Libsail

module Argument : sig
  (** An argument of an encoded instruction: an operand it binds, or a constant such as an enum
      member, as written. *)
  type t =
    | Operand of string
    | Constant of string
end

(** An instruction as a clause of the encoding mapping gives it: the constructor and arguments on
    the left, the fields of the word on the right from the most significant bit, and the source of
    the clause's guard, if it has one. *)
type t =
  { constructor : string
  ; arguments : Argument.t list
  ; fields : Word_field.t list
  ; condition : string option
  ; location : Parse_ast.l
  }

(** The instruction as its encoding clause takes it apart, such as [RTYPE(rs2, rs1, rd, ADD)]. *)
val to_string : t -> string

(** What a clause that takes a constructor apart with these argument patterns binds, if it
    applies to every word of the instruction: the constructor is the instruction's, and each
    pattern binds or ignores its argument or is the instruction's constant. *)
val bindings : t -> string * Sail_ast.Argument.t list -> (string * Argument.t) list option

(** The instructions of the clauses of an encoding mapping. A field on the right is fixed bits, an
    operand, or a mapping applied to an operand (that operand) or to constants only (ignored bits).
    Unguarded clauses must differ in their fixed bits. *)
val read : Type_check.Env.t -> Sail_ast.Mapping_clause.t list -> t list
