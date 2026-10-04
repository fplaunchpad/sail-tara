(** The input lines over a run: the initial lines until the first entry of a key script, then the
    lines of each entry from its step on. *)

open! Core

type t

(** The same lines for the whole run. *)
val constant : Keys.t -> t

(** Read a key script and put it after the [initial] lines. Each line is [STEP KEYS]; the steps
    are decimal and strictly increasing. [;] starts a comment, and blank lines are allowed. *)
val load : Filename.t -> initial:Keys.t -> t Or_error.t

(** The lines for the instruction executed after [retired] retirements: those of the last entry
    whose step is at most [retired], else the initial lines. *)
val at : t -> retired:int -> Keys.t
