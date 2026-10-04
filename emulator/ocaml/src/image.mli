(** Program images, loaded into the machine from address 0: raw bytes ([.bin]), or big-endian
    16-bit words of 1 to 4 hex digits ([.hex]), where [;] starts a comment. *)

open! Core

val load : Filename.t -> unit Or_error.t
