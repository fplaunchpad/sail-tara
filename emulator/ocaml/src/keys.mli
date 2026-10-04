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
  [@@deriving enumerate, equal]

  (** The position of the line in {!all}: its bit number. *)
  val index : t -> int

  (** The status line's letter for the line: [U], [D], [L], [R] or [Q]. *)
  val letter : t -> char
end

(** The lines held at one time. *)
type t [@@deriving equal]

(** No line held. *)
val none : t

val of_lines : Line.t list -> t
val mem : t -> Line.t -> bool

(** The byte a read of the input port returns. *)
val to_int : t -> int

(** The lines as [--keys] and key scripts spell them: a number from 0 to 31, in decimal or as [0x]
    hex. *)
val of_string : string -> t Or_error.t
