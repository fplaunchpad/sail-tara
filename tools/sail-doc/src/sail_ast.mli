open Libsail
open Type_check
open Extraction.Ast

module Function_clause : sig
  type t =
    { pattern : tannot pat
    ; body : tannot exp
    }
end

module Mapping_clause : sig
  type t =
    { left : tannot mpat
    ; right : tannot mpat
    ; location : Parse_ast.l
    }
end

val id_string : id -> string
val fail_at : Parse_ast.l -> string -> 'a
val pat_location : tannot pat -> Parse_ast.l
val mpat_location : tannot mpat -> Parse_ast.l
val unwrap_pat : tannot pat -> tannot pat
val unwrap_mpat : tannot mpat -> tannot mpat
val constructor_pat : tannot pat -> (string * tannot pat list) option
val constructor_mpat : tannot mpat -> (string * tannot mpat list) option
val pattern_args : tannot pat list -> tannot pat list
val expression_args : tannot exp list -> tannot exp list
val expression_id : tannot exp -> string option
val decode_result : tannot exp -> (string * string list) option
val literal_bits : Parse_ast.l -> lit -> string
val width_of_pat : Type_check.Env.t -> tannot pat -> int
val width_of_exp : Type_check.Env.t -> tannot exp -> int
val function_clauses : Type_check.typed_ast -> string -> Function_clause.t list
val mapping_clauses : Type_check.typed_ast -> string -> Mapping_clause.t list
