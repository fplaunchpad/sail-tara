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
    ; body : tannot exp
    ; guard : tannot exp option
    ; annotation : unit def_annot
    ; documented : bool
    ; location : Parse_ast.l
    }
end

(** A two-way clause of a mapping, named [name], preserving guards on both sides. *)
module Mapping_clause : sig
  type t =
    { name : string
    ; left : tannot mpat
    ; right : tannot mpat
    ; guards : tannot exp list
    ; annotation : unit def_annot
    ; documented : bool
    ; location : Parse_ast.l
    }
end

(** An argument of a constructor in a pattern: a name it binds, a constant (an enum member or a
    literal, as written), a wildcard, or another pattern. *)
module Argument : sig
  type t =
    | Binder of string
    | Constant of string
    | Wildcard
    | Other
  [@@deriving equal]

  val of_pat : Env.t -> tannot pat -> t
  val of_mpat : Env.t -> tannot mpat -> t
end

val id_string : id -> string
val fail_at : Parse_ast.l -> string -> 'a
val pat_location : tannot pat -> Parse_ast.l
val mpat_location : tannot mpat -> Parse_ast.l
val exp_location : tannot exp -> Parse_ast.l

(** The file a location is in. *)
val source_file : Parse_ast.l -> string

(** The text a location spans, and the text from the start of one location to the end of
    another. *)
val source_text : Parse_ast.l -> string

val source_span : Parse_ast.l -> Parse_ast.l -> string

(** The text between the end of one location and the start of a later one. *)
val source_between : Parse_ast.l -> Parse_ast.l -> string option

(** Whether two locations start at the same place. *)
val same_start : Parse_ast.l -> Parse_ast.l -> bool

(** A pattern without its type annotations and bindings of the whole. *)
val unwrap_pat : tannot pat -> tannot pat

val unwrap_mpat : tannot mpat -> tannot mpat

(** A constructor application's constructor and arguments: none for unit, or each element of a
    tuple. *)
val constructor_pat : tannot pat -> (string * tannot pat list) option

val constructor_mpat : tannot mpat -> (string * tannot mpat list) option

(** The bits of a binary or hexadecimal literal, most significant first. *)
val literal_bits : Parse_ast.l -> lit -> string

(** The width of a bitvector type, if it is fixed. *)
val bits_width : Env.t -> typ -> int option

val width_of_mpat : Env.t -> tannot mpat -> int

(** Every function clause, every two-way mapping clause and every documented anchor. *)
val function_clauses : typed_ast -> Function_clause.t list

val mapping_clauses : typed_ast -> Mapping_clause.t list

(** A key that orders locations by source position: files in the order their definitions,
    constructors and clauses first appear in the AST, then by offset within a file. *)
val order : typed_ast -> Parse_ast.l -> int * int
