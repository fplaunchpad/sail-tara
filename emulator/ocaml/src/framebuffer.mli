(** The machine's 64 x 64 monochrome framebuffer: a bit per pixel, at 0x600 to 0x7FF. Reading a
    pixel through the model takes about ten microseconds, too long to read them all for each frame
    of a game. A [t] remembers the bytes it saw, so that {!refresh} reads again only the pixels of
    the bytes that have changed. *)

(** Pixels in a row, and rows. *)
val size : int

type t

(** Every pixel as the machine has it now. Reading them all takes about 50 milliseconds. *)
val read : unit -> t

(** The framebuffer as the machine has it now, given what was read before. *)
val refresh : t -> t

(** The pixel at column [x] and row [y] when [t] was read; row 0 is the bottom row. *)
val pixel : t -> x:int -> y:int -> Machine.Pixel.t
