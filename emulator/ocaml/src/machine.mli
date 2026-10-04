(** The TARA machine: the Sail model, compiled through [emulator/host.sail]. Hides the generated
    names and the model's bit lists. The model's state is global: these functions read and change
    it, and nothing else does. *)

(** The result of one step. *)
module Step : sig
  type t =
    | Retired
    | Stopped (** The CPU was already halted. *)
    | Illegal (** An unassigned opcode; PC has advanced past it. *)
  [@@deriving sexp_of]
end

(** A pixel of the framebuffer. *)
module Pixel : sig
  type t =
    | Lit
    | Dark
  [@@deriving equal]
end

(** Whether the CPU can execute instructions: it halts on HLT. *)
module Cpu : sig
  type t =
    | Running
    | Halted
end

(** Start the model at power-on: registers and memory cleared, PC 0. *)
val start : unit -> unit

(** Write a byte of RAM, as a program loader does. *)
val poke : address:int -> int -> unit

(** A byte of RAM, without the input port. *)
val peek : address:int -> int

(** The pixel at column [x] and row [y] of the framebuffer; row 0 is the bottom row. Each call
    takes about ten microseconds. *)
val pixel : x:int -> y:int -> Pixel.t

val pc : unit -> int
val cpu : unit -> Cpu.t

(** Execute one instruction with the given input lines (bits 0-4). *)
val step : keys:int -> Step.t

(** The assembly text of an instruction word, [illegal] for an unassigned opcode. *)
val disasm : int -> string

(** The trace line of the last step. *)
val trace : unit -> string

(** The final state: pc, r0-r7 and mem lines. *)
val dump : unit -> string
