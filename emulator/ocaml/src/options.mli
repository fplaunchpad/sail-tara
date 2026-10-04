(** The command line: its flags, and what they select once checked against each other. *)

open! Core

(** What to do. *)
module Mode : sig
  type t =
    | Disassemble (** [--disasm-all]: print the assembly of every instruction word. *)
    | Batch of Batch.Options.t (** Run an image, and print what happened. *)
    | Interactive of Interactive.Options.t (** [-i]: play an image in the terminal. *)
end

(** The flags and the IMAGE argument. Fails if they do not make a {!Mode.t}: [--disasm-all] takes
    no IMAGE and no other flag, and [-i] takes none of [--trace], [--fb], [--keys] and
    [--key-script]. *)
val param : Mode.t Or_error.t Command.Param.t
