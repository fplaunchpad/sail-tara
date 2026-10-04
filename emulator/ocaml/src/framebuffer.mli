(** The machine's 64 x 64 monochrome framebuffer: a bit per pixel, at 0x600 to 0x7FF. Reading a
    pixel through the model takes about ten microseconds, too long to read them all for each frame
    of a game. A [t] remembers the bytes it saw, and reads again only the pixels of the bytes that
    have changed. *)

(** Pixels in a row, and rows. *)
val size : int

type t

(** A framebuffer that has seen nothing yet: the first {!refresh} reads every pixel. *)
val create : unit -> t

(** Bring the pixels up to date with the machine. *)
val refresh : t -> unit

(** Whether the pixel at column [x] and row [y] was set at the last {!refresh}; row 0 is the
    bottom row. *)
val pixel : t -> x:int -> y:int -> bool
