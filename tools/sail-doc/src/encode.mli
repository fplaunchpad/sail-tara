open Libsail

val validate : Type_check.Env.t -> Decode.t list -> Sail_ast.Function_clause.t list -> unit
