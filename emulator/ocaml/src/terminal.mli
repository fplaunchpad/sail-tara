(** The terminal, taken over by a full-screen program: raw mode on the alternate screen. *)

open! Core

(** Whether standard input and standard output are both terminals; the error says so if not. *)
val check : unit -> unit Or_error.t

(** Run [f] with the terminal in raw mode on the alternate screen, with the cursor hidden. Raw
    mode is no echo, no line editing and no signal keys, so that Ctrl-C reads as a byte.

    The terminal is put back as it was when [f] returns or raises. SIGINT, SIGTERM and SIGHUP do
    not stop the process while [f] runs: they make {!interrupted} say which, and [f] is expected
    to return soon after. The signal is then sent again to end the process, once the terminal is
    back. A second signal ends the process at once. A signal that was being ignored stays so.

    Fails if the terminal cannot be set up, or stops taking output or input while [f] runs. *)
val with_screen : (unit -> 'a) -> 'a Or_error.t

(** The signal that has asked the program to stop, if one has. *)
val interrupted : unit -> Signal.t option

(** Whether the terminal changed size. *)
module Size_change : sig
  type t =
    | Resized
    | Unchanged
end

(** Whether the terminal has been resized since the last call, which leaves the screen to be drawn
    again. *)
val resized : unit -> Size_change.t

(** Send [text] to the screen. *)
val write : string -> unit

(** What the terminal sent. *)
module Input : sig
  type t =
    | Bytes of string
    | Nothing (** Nothing was sent in the time allowed. *)
    | Closed (** The terminal has gone away. *)
end

(** Wait up to [timeout] for the terminal to send something. *)
val read : timeout:Time_ns.Span.t -> Input.t
