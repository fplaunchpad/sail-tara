(** Running the generated model on a concrete machine.

    The generated functions live in Sail's free monad [M]. [liftState] interprets it as a state
    monad over the generated register record. Everything here is closed, so [vm_compute] runs it. *)
From Stdlib Require Import List ZArith.
From stdpp Require Import base list_numbers bitvector.definitions.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara.
Import ListNotations.
Open Scope Z_scope.

(** The state an action runs on: the generated registers (GPR, PC, MEM, HALTED, KEYS and nextPC)
    plus Sail's memory and tag maps, which TARA does not use. *)
Definition machine : Type := sequential_state regstate.

(** The result of an action and the state after it. [None] if the action fails, throws or is
    nondeterministic. *)
Definition exec {A} (m : M A) (s : machine) : option (A * machine) :=
  match liftState register_accessors m s default_choice with
  | [(Value a, s', _)] => Some (a, s')
  | _ => None
  end.

(** The state after an action, forgetting its result. *)
Definition after {A} (m : M A) (s : machine) : option machine :=
  '(_, s) ← exec m s;
  Some s.

(** Power-on: [sail_model_init] gives every register an undefined value, which the default choice
    source resolves to zero or false. So the registers and memory are zero, PC is 0 and the CPU is
    not halted. ([init_regstate] alone starts halted: stdpp's inhabitant of [bool] is [true].) *)
Definition power_on : option machine :=
  after (sail_model_init tt) (init_state init_regstate).

(** Store [words] at [addr], [addr + 2] and so on, with the model's [write_word]: big-endian. *)
Fixpoint load (addr : Z) (words : list (mword 16)) (s : machine) : option machine :=
  match words with
  | [] => Some s
  | w :: words =>
      s ← after (write_word (mword_of_int addr) w) s;
      load (addr + 2) words s
  end.

(** All five input lines low. *)
Definition no_keys : mword 5 := 'b"00000".

(** [step] until the CPU halts: the number of instructions retired and the halted machine. [fuel]
    bounds the number of steps. [None] if it runs out, if [step] returns [Illegal], or if the model
    fails. *)
Fixpoint run (fuel : nat) (keys : mword 5) (s : machine) : option (nat * machine) :=
  match fuel with
  | O => None
  | S fuel =>
      match exec (step keys) s with
      | Some (Stopped _, s) => Some (0%nat, s)
      | Some (Retired _, s) =>
          '(n, s) ← run fuel keys s;
          Some (S n, s)
      | _ => None
      end
  end.

(** Power on, load [program] at address 0 and run it to its halt. *)
Definition run_program (fuel : nat) (program : list (mword 16)) : option (nat * machine) :=
  s ← power_on;
  s ← load 0 program s;
  run fuel no_keys s.

(** What the tests compare: PC, the registers R0 to R7 and the halt latch, as plain integers. *)
Record observation := {
  pc : Z;
  gpr : list Z;
  halted : bool;
}.

Definition observe (s : machine) : observation :=
  let rs := s.(ss_regstate) in
  {| pc := bv_unsigned (bitvector_16_s rs PC);
     gpr := map (fun r => bv_unsigned (vec_access_dec (vector_8_bitvector_16_s rs GPR) r))
                (seqZ 0 8);
     halted := bool_s rs HALTED |}.
