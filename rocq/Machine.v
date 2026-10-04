(** Machines, and running the model's actions on them.

    Every generated function is an action in Sail's free monad [M]. The model only reads and writes
    registers, so an action is a tree of [Read_reg] and [Write_reg] nodes, and [eval] runs it on a
    register record directly. [exec] runs an action on a machine: the generated registers plus
    Sail's own memory and tag maps, which TARA does not use. [exec_sound] shows that [exec] agrees
    with Sail's interpretation of the monad, [liftState], for every choice source. *)
From Stdlib Require Import List ZArith.
From stdpp Require Import base.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara.
Import ListNotations.
Open Scope Z_scope.

Definition machine : Type := sequential_state regstate.

Definition regs (s : machine) : regstate := ss_regstate s.

(** [s] with its registers replaced. *)
Definition with_regs (s : machine) (rs : regstate) : machine :=
  {| ss_regstate := rs;
     ss_memstate := ss_memstate s;
     ss_tagstate := ss_tagstate s;
     ss_output := ss_output s |}.

(** The registers of a machine. [lines] are the five input lines (the register KEYS). *)
Definition pc (s : machine) : mword 16 := register_lookup PC (regs s).
Definition next_pc (s : machine) : mword 16 := register_lookup nextPC (regs s).
Definition lines (s : machine) : mword 5 := register_lookup KEYS (regs s).
Definition halted (s : machine) : bool := register_lookup HALTED (regs s).
Definition gpr (s : machine) : vec (mword 16) 8 := register_lookup GPR (regs s).
Definition mem (s : machine) : vec (mword 8) 2048 := register_lookup MEM (regs s).

(** * Running actions *)

(** Run [m] from register state [rs]. Reading memory, choosing, failing and throwing are outside
    the fragment, so they give [None]; the model uses none of them. *)
Fixpoint eval {A} (m : M A) (rs : regstate) : option (A * regstate) :=
  match m with
  | Done a => Some (a, rs)
  | Read_reg r k => eval (k (register_lookup r rs)) rs
  | Write_reg r v k => eval k (register_set r v rs)
  | _ => None
  end.

(** The result of an action and the machine after it. [Some] means that the action completed: it
    did not fail, throw or choose. *)
Definition exec {A} (m : M A) (s : machine) : option (A * machine) :=
  '(a, rs) ← eval m (regs s);
  Some (a, with_regs s rs).

Lemma liftState_eval {A} (m : M A) (s : machine) cs a rs' :
  eval m (regs s) = Some (a, rs') ->
  liftState register_accessors m s cs = [(Value a, with_regs s rs', cs)].
Proof.
  revert s; induction m; intros s0 Hev; cbn [eval] in Hev; try discriminate.
  - injection Hev as <- <-. destruct s0; reflexivity.
  - cbn [liftState register_accessors read_regvalS]. unfold bindS, readS, returnS. simpl.
    rewrite app_nil_r. eauto.
  - cbn [liftState register_accessors write_regvalS]. unfold seqS, bindS, readS, updateS, returnS.
    simpl. rewrite app_nil_r. exact (IHm (with_regs s0 (register_set r r0 (regs s0))) Hev).
Qed.

(** Soundness: when [exec] completes, Sail's [liftState] gives that one outcome, whatever the choice
    source, and leaves the source as it found it. *)
Theorem exec_sound {A} (m : M A) s a s' :
  exec m s = Some (a, s') ->
  forall cs, liftState register_accessors m s cs = [(Value a, s', cs)].
Proof.
  unfold exec. destruct (eval m (regs s)) as [[a0 rs0]|] eqn:E; cbn; [|discriminate].
  intros [= <- <-] cs. apply liftState_eval, E.
Qed.

(** * Fetching *)

(** The word [step keys] fetches from [s]: what [read_word] returns at PC once the input lines have
    been set to [keys]. The word at 0x5FE has the input lines as its low byte, so [keys] matters. *)
Definition fetch (keys : mword 5) (s : machine) : option (mword 16) :=
  '(_, s1) ← exec (write_reg KEYS keys) s;
  '(raw, _) ← exec (read_word (pc s1)) s1;
  Some raw.

(** * Power-on *)

(** A machine after power-on and reset: registers and memory zero, PC 0, not halted. The zeros are
    what Sail's [init_regstate] holds, and what its [sail_model_init] gives under the default
    choice source. [init_regstate] alone starts halted, because stdpp's inhabitant of [bool] is
    [true]; the reset clears that. *)
Definition power_on : option machine :=
  '(_, s) ← exec (reset tt) (init_state init_regstate);
  Some s.
