(** The ANSI control sequences that the interactive mode sends to the terminal. *)

(** A 24-bit colour. *)
module Colour : sig
  type t =
    { red : int
    ; green : int
    ; blue : int
    }
end

val enter_alternate_screen : string
val leave_alternate_screen : string
val hide_cursor : string
val show_cursor : string
val clear_screen : string

(** Back to the default colours. *)
val reset_colours : string

(** Move the cursor; the top left of the screen is row 1, column 1. *)
val move_to : row:int -> column:int -> string

val erase_to_end_of_line : string

(** Colour the characters that follow. *)
val colours : foreground:Colour.t -> background:Colour.t -> string
