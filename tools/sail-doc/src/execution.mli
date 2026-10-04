open Libsail

(** What an instruction does: the statements of the body of the first clause of the function
    [execute] among [functions] that applies to it, in [notation]. *)
val read
  :  env:Type_check.Env.t
  -> notation:Notation.t
  -> functions:Sail_ast.Function_clause.t list
  -> execute:string
  -> Encoding.t
  -> string list option
