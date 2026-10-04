(** The options of the subcommands [run] and [play], as the flags and the IMAGE argument give them.
    [disasm] takes none. *)

open! Core

val run : Batch.Options.t Command.Param.t
val play : Interactive.Options.t Command.Param.t
