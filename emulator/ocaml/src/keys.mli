(** The five input lines: the low bits of a byte read of the input port. *)

open! Core

(** One input line. *)
module Line : sig
  (** In the order of their bits, from bit 0, and of the status line's letters. *)
  type t =
    | Up
    | Down
    | Left
    | Right
    | Quit
  [@@deriving enumerate]

  include Comparable.S_plain with type t := t

  (** The status line's letter for the line: [U], [D], [L], [R] or [Q]. *)
  val letter : t -> char

  (** The line that a key drives: W, A, S and D, and Q for QUIT, in either case. *)
  val of_key : char -> t option

  (** The line that an arrow key drives, by the last character of its escape sequence: [A] for up,
      [B] for down, [C] for right and [D] for left. *)
  val of_arrow : char -> t option
end

(** Whether a line is held. *)
module State : sig
  type t =
    | Held
    | Released
end

(** The lines held at one time. *)
type t [@@deriving equal]

(** No line held. *)
val none : t

val of_lines : Line.t list -> t
val state : t -> Line.t -> State.t

(** The byte a read of the input port returns. *)
val to_int : t -> int

(** The lines as [--keys] and key scripts spell them: a number from 0 to 31, in decimal or as [0x]
    hex. *)
val of_string : string -> t Or_error.t
