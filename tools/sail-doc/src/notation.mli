open Libsail
open Extraction.Ast

(** How to write the model's functions, registers and constants in a reference card's notation, by
    name. A template such as [R[{0}]] puts the arguments in place of [{0}], [{1}] and so on; a
    template [{0} OP {1}] is an infix operator. *)
type t

val find : t -> string -> string option

val written_operator
  :  Parse_ast.l
  -> Type_check.tannot exp
  -> Type_check.tannot exp
  -> string option

(** The notations the model gives with [@notation template] in a doc comment on a function,
    value specification, register or [let], over names for Sail's bit constants. *)
val read : Type_check.typed_ast -> t
