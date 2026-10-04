(** The framebuffer on the terminal, drawn with upper half blocks: two rows of pixels to a line of
    characters, the upper pixel as the foreground and the lower as the background. A status line
    is below it. Only what has changed since the last draw is sent. *)

type t

(** A display that has drawn nothing: the first {!draw} clears the screen and paints everything. *)
val create : unit -> t

(** Forget what the terminal shows, as when it has been resized: the next {!draw} clears the screen
    and paints everything again. *)
val reset : t -> unit

(** Read the machine's framebuffer again. *)
val refresh : t -> unit

(** The control sequences that bring the terminal up to date with the last {!refresh}, and put
    [status] below the framebuffer. The status line is written again if it has changed, or if
    [repeat_status] says so. Empty if there is nothing to write. *)
val draw : t -> status:string -> repeat_status:bool -> string
