(** Running a loaded program to completion. *)

open! Core

(** Why a run ended: the dump's status line and the exit code. *)
module Status : sig
  type t =
    | Halted
    | Limit
    | Illegal
  [@@deriving string]

  val exit_code : t -> int
end

(** Step the machine until it halts, [max_steps] instructions retire (0: no limit), or an illegal
    opcode is fetched. With [trace], print a trace line per step. Returns the status and the
    number of instructions retired. *)
val run : max_steps:int -> trace:bool -> Status.t * int
