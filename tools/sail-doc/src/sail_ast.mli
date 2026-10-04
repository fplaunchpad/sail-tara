(** What the plugin reads from Sail's typed AST. Its failures are Sail errors at a source location. *)

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

(** The file a location is in. *)
val source_file : Parse_ast.l -> string

(** A pattern without its type annotations and bindings of the whole. *)
val unwrap_pat : tannot pat -> tannot pat

val unwrap_mpat : tannot mpat -> tannot mpat
val is_unit_mpat : tannot mpat -> bool

(** A constructor application's constructor and arguments: none for unit, or each element of a
    tuple. *)
val constructor_mpat : tannot mpat -> (string * tannot mpat list) option

(** What a decode clause returns: [Some (constructor, operand names)] for [Some(C(...))], and
    [None] for [None()]. *)
val decode_result : tannot exp -> (string * string list) option

(** The bits of a binary or hexadecimal literal, most significant first. *)
val literal_bits : Parse_ast.l -> lit -> string

val width_of_pat : Type_check.Env.t -> tannot pat -> int

(** The clauses of the function or mapping [name], in source order. *)
val function_clauses : Type_check.typed_ast -> string -> Function_clause.t list

val mapping_clauses : Type_check.typed_ast -> string -> Mapping_clause.t list
