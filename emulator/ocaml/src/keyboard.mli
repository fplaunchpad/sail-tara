(** The keys of a terminal. They drive the input lines: the arrows or W, A, S and D move, Q quits.
    ESC on its own and Ctrl-C leave the emulator.

    Terminals send no key-up, so a line stays held for 150 ms after its key was last pressed. *)

open! Core

type t

val create : unit -> t

(** Take the bytes that the terminal sent at time [now]. The bytes of an arrow key's escape
    sequence may arrive in several reads. *)
val feed : t -> now:Time_ns.t -> string -> unit

(** When the escape at the end of the bytes taken so far, if there is one, stops waiting for the
    rest of its sequence. *)
val deadline : t -> Time_ns.t option

(** Take that escape for the Escape key if it has waited too long at time [now]. *)
val expire : t -> now:Time_ns.t -> unit

(** Whether a key has asked to leave. *)
val leaving : t -> bool

(** The input lines held at time [now]. *)
val held : t -> now:Time_ns.t -> Keys.t
