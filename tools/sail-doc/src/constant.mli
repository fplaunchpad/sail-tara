open Core
open Libsail
open Type_check
open Extraction.Ast

type t

val create : Interactive.State.istate -> t Or_error.t
val eval : t -> tannot mpat -> string Or_error.t
