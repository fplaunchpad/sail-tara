(** A run of the loaded program: its steps, counted against a limit. The machine is global, so there
    is one run at a time; a [t] is the count of its steps and the result of the last. *)

(** Why a run ended: the dump's status line and the exit code. *)
module Status : sig
  type t =
    | Halted
    | Limit
    | Illegal
  [@@deriving string]

  val exit_code : t -> int
end

type t

(** A run from the machine's present state. It ends after [max_steps] instructions retire (0: no
    limit), when the CPU halts, or when an illegal opcode is fetched. *)
val create : max_steps:int -> t

(** The number of instructions retired so far. *)
val retired : t -> int

(** Why the run has ended, or [None] while it can go on. *)
val status : t -> Status.t option

(** Execute one instruction with the given input lines; the run after it. The run must not have
    ended. *)
val step : t -> keys:Keys.t -> t
