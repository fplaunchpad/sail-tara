open Libsail

(** An instruction's assembly syntax, from the first clause of the mapping [assembly] among
    [mappings] that applies to it. Its right side may concatenate strings and mappings applied to
    an operand, which shows the operand's name, or to a constant or unit, which shows the text of
    the mapping's clause for it, as for a mnemonic or a separator. *)
val read
  :  env:Type_check.Env.t
  -> mappings:Sail_ast.Mapping_clause.t list
  -> assembly:string
  -> Encoding.t
  -> string option
