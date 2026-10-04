open Libsail

module Expected_bit : sig
  type t =
    | Constant of char
    | Operand of int
    | Padding
end

type t =
  { constructor : string
  ; opcode_bits : string
  ; fields : Instruction.Field.t list
  ; argument_names : string list
  ; expected_bits : Expected_bit.t list
  ; location : Parse_ast.l
  ; source_file : string
  }

val extract : Type_check.Env.t -> Sail_ast.Function_clause.t list -> t list
