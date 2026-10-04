(** The clock that paces play. It never goes back, whatever happens to the
    system's time. Its times mean nothing but their differences. *)

open! Core

val now : unit -> Time_ns.t
