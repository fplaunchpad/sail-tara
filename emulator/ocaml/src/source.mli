(** The files the emulator is given to read, program images and key scripts. Their text is line
    oriented: [;] starts a comment, and fields are separated by whitespace. *)

open! Core

(** The contents of a file. The error says why it could not be read. *)
val read : Filename.t -> string Or_error.t

(** The lines of [text] that have fields, as their line numbers (from 1) and fields. Comments are
    dropped, and so are blank lines. *)
val fields : string -> (int * string list) list
