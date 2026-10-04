open Libsail

(** What an instruction does: the statements of the body of the first clause of the function
    [execute] among [functions] that applies to it, as written. Each binding of a [let] or [var]
    is a statement of its own, and a body of unit has none. *)
val read
  :  env:Type_check.Env.t
  -> functions:Sail_ast.Function_clause.t list
  -> execute:string
  -> Encoding.t
  -> string list option
