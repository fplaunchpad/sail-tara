open Libsail
open Extraction.Ast

(** How to write the model's functions, registers and constants in a reference card's notation, by
    name. A template such as [R[{0}]] puts the arguments in place of [{0}], [{1}] and so on; a
    template [{0} OP {1}] is an infix operator. *)
type t

(** The notations the model gives with the attribute [$[notation "template"]] on a function,
    value specification, register or [let], over notations for Sail's library (sign and zero
    extension, shifts, slices). *)
val read : Type_check.typed_ast -> t

(** The statements of a function body in the notation, a statement each: an assignment, a call
    or a conditional. Operators keep the source's spelling, bit literals become numbers, and a
    concatenation with zeros on the left is a zero extension. A construct the notation does not
    cover is shown as its source. A body of unit has no statements. *)
val statements : t -> Type_check.tannot exp -> string list
