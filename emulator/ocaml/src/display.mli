(** The framebuffer on the terminal, drawn with upper half blocks: two rows of pixels to a line of
    characters, the upper pixel as the foreground and the lower as the background. A status line
    is below it. A [t] is what the machine's framebuffer was when it was read and what the
    terminal shows, so that a draw sends only what has changed. *)

(** When {!draw} writes the status line. *)
module Status_rewrite : sig
  type t =
    | Always
    | When_changed
end

type t

(** The machine's framebuffer as it is now, with nothing drawn yet: the first {!draw} clears the
    screen and paints everything. *)
val create : unit -> t

(** Forget what the terminal shows, as when it has been resized: the next {!draw} clears the screen
    and paints everything again. *)
val reset : t -> t

(** Read the machine's framebuffer again. *)
val refresh : t -> t

(** The control sequences that bring the terminal up to date with the last {!refresh}, and put
    [status] below the framebuffer; empty if there is nothing to write. The terminal is then
    showing what the returned [t] says. The status line is written when it has changed, or always
    if [rewrite] says so. *)
val draw : t -> status:string -> rewrite:Status_rewrite.t -> string * t
