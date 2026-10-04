(** Each instruction's assembly syntax, as [(constructor, template)], from the clauses of the
    mapping [assembly] among [mappings]. A template is a clause's text with each printed operand
    shown by its name in decode (or in the clause, if decode computes it), and each mapping from
    unit, such as a separator, inlined; the right side of a clause may only concatenate those and
    string literals. *)
val read
  :  mappings:Sail_ast.Mapping_clause.t list
  -> assembly:string
  -> Decode.t list
  -> (string * string) list
