(** Running a program to its end, and printing what happened: the trace lines, the status and the
    number of steps, the final state, and the framebuffer. *)

open! Core

(** Whether to print a line for each step that fetched an instruction. *)
module Trace : sig
  type t =
    | Print_steps
    | No_trace
end

(** Whether to print the framebuffer after the final state. *)
module Framebuffer_dump : sig
  type t =
    | Print_framebuffer
    | No_framebuffer
end

module Options : sig
  type t =
    { image : Filename.t
    ; max_steps : int (** 0: no limit. *)
    ; trace : Trace.t
    ; keys : Keys.t (** The input lines, until the key script changes them. *)
    ; key_script : Filename.t option
    ; framebuffer : Framebuffer_dump.t
    }
end

(** Load the image and the key script, run, and print. Returns the exit status of the run's end.
    Prints nothing if the image or the key script is not valid. *)
val run : Options.t -> int Or_error.t
