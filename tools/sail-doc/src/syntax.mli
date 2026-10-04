open Libsail

(** Each instruction's assembly syntax, as [(constructor, template)], from the clauses of the
    assembly mapping. A template is the clause's text with each printed operand shown by its
    name in decode, and each mapping from unit, such as a separator, inlined; the right side of a
    clause may only concatenate those and string literals. *)
val read
  :  ast:Type_check.typed_ast
  -> Decode.t list
  -> Sail_ast.Mapping_clause.t list
  -> (string * string) list
