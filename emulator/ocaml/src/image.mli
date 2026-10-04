(** Program images, loaded into the machine from address 0: raw bytes ([.bin]), or big-endian
    16-bit words of 1 to 4 hex digits ([.hex]). At most 2048 bytes. *)

open! Core

(** Load the image into the machine's memory. Nothing is loaded if the image is not valid. *)
val load : Filename.t -> unit Or_error.t
