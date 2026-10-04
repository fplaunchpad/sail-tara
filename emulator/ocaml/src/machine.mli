(** The TARA machine: the Sail model, compiled through [emulator/host.sail]. Hides the generated
    names and the model's bit lists. *)

open! Core

(** The result of one step. *)
module Step : sig
  type t =
    | Retired
    | Stopped (** The CPU was already halted. *)
    | Illegal (** An unassigned opcode; PC has advanced past it. *)
  [@@deriving sexp_of]
end

(** Start the model at power-on: registers and memory cleared, PC 0. *)
val start : unit -> unit

(** Write a byte of RAM, as a program loader does. *)
val poke : address:int -> int -> unit

val halted : unit -> bool

(** Execute one instruction with the given input lines (bits 0-4). *)
val step : keys:int -> Step.t

(** The trace line of the last step. *)
val trace : unit -> string

(** The final state: pc, r0-r7 and mem lines. *)
val dump : unit -> string
