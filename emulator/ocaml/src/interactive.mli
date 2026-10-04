(** Playing a program in the terminal: the framebuffer is drawn about 30 times a second, with a
    status line below it, and the keyboard drives the input lines. *)

open! Core

module Options : sig
  type t =
    { image : Filename.t
    ; max_steps : int (** 0: no limit. *)
    ; hz : int (** Instructions per second; 0: as many as the time allows. *)
    }
end

(** Load the image and play it until the user leaves with ESC or Ctrl-C. The program may end
    before that, by halting, by reaching the step limit or on an illegal opcode; its last frame
    stays up. Returns the exit status: that of the run's end, 0 if it was still going.

    Fails, before touching the terminal, if there is none or the image is not valid. Fails
    afterwards if the terminal goes away. *)
val run : Options.t -> int Or_error.t
