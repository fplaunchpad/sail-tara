(** What the plugin reads from Sail's typed AST. Its failures are Sail errors at a source
    location. *)

open Libsail
open Type_check
open Extraction.Ast

(** A clause of a function, named [name]. *)
module Function_clause : sig
  type t =
    { name : string
    ; pattern : tannot pat
    ; guarded : bool
    ; body : tannot exp
    ; documented : bool
    ; location : Parse_ast.l
    }
end

(** A two-way clause of a mapping, named [name]. *)
module Mapping_clause : sig
  type t =
    { name : string
    ; left : tannot mpat
    ; right : tannot mpat
    ; documented : bool
    ; location : Parse_ast.l
    }
end

(** A [$anchor] with a documentation comment. *)
module Anchor : sig
  type t =
    { name : string
    ; location : Parse_ast.l
    }
end

val id_string : id -> string
val fail_at : Parse_ast.l -> string -> 'a
val pat_location : tannot pat -> Parse_ast.l
val mpat_location : tannot mpat -> Parse_ast.l
val exp_location : tannot exp -> Parse_ast.l

(** The file a location is in. *)
val source_file : Parse_ast.l -> string

(** A pattern without its type annotations and type variable bindings. *)
val unwrap_pat : tannot pat -> tannot pat

val unwrap_mpat : tannot mpat -> tannot mpat
val is_unit_mpat : tannot mpat -> bool

(** The constructor a pattern takes apart, if it is a constructor application. *)
val constructor_pat : tannot pat -> string option

(** A constructor application's constructor and arguments: none for unit, or each element of a
    tuple. *)
val constructor_mpat : tannot mpat -> (string * tannot mpat list) option

(** What a decode clause returns: [Some (constructor, operands)] for [Some(C(...))], and [None] for
    [None()]. *)
val decode_result : tannot exp -> (string * tannot exp list) option

(** The bits of a binary or hexadecimal literal, most significant first. *)
val literal_bits : Parse_ast.l -> lit -> string

val width_of_pat : Type_check.Env.t -> tannot pat -> int

(** Every function clause, every two-way mapping clause and every documented anchor. *)
val function_clauses : Type_check.typed_ast -> Function_clause.t list

val mapping_clauses : Type_check.typed_ast -> Mapping_clause.t list
val anchors : Type_check.typed_ast -> Anchor.t list

(** A key that orders locations by source position: files in the order their definitions,
    constructors and clauses first appear in the AST, then by offset within a file. *)
val order : Type_check.typed_ast -> Parse_ast.l -> int * int
