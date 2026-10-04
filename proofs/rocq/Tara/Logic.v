(** A small program logic for the model's actions.

    [Safe I m] says that the action [m] completes from every state satisfying [I] and ends in a
    state that satisfies [I]: progress and preservation in one. Its rules follow the structure of
    the generated code, and the tactic [safe] applies them. With [I] true everywhere it says that
    [m] always completes. [exec_total] and [exec_safe] carry the results over to [exec]. *)
From Stdlib Require Import List ZArith.
From stdpp Require Import base.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara Machine Decode.
Import ListNotations.
Open Scope Z_scope.

(** * Evaluation *)

Lemma eval_bind {A B} (m : M A) (f : A -> M B) rs :
  eval (m >>= f) rs = match eval m rs with Some (a, rs') => eval (f a) rs' | None => None end.
Proof. revert rs; induction m; intros rs; simpl; try reflexivity; auto. Qed.

Lemma eval_bind0 {B} (m : M unit) (n : M B) rs :
  eval (m >> n) rs = match eval m rs with Some (_, rs') => eval n rs' | None => None end.
Proof. unfold bind0. rewrite eval_bind. destruct (eval m rs) as [[[] ?]|]; reflexivity. Qed.

(** Evaluate an action step by step. *)
Ltac eval_simp :=
  repeat first
    [ rewrite eval_bind | rewrite eval_bind0
    | progress cbn [eval read_reg write_reg returnM returnm Prompt_monad.read_reg
                    Prompt_monad.write_reg] ].

(** Read a register back from a record that has been written. *)
Ltac lookup_simp :=
  repeat first [rewrite register_lookup_set | rewrite irrelevant_register_set by reflexivity].

(** * Progress and preservation *)

(** From any register state satisfying [I], [m] completes in one that satisfies [I]. *)
Definition Safe {A} (I : regstate -> Prop) (m : M A) : Prop :=
  forall rs, I rs -> exists a rs', eval m rs = Some (a, rs') /\ I rs'.

(** [m] runs to completion from any state. *)
Abbreviation Total m := (Safe (fun _ => True) m).

Lemma exec_total {A} (m : M A) : Total m -> forall s, exists a s', exec m s = Some (a, s').
Proof.
  intros H s. destruct (H (regs s) I) as (a & rs' & Hv & _).
  exists a, (with_regs s rs'). unfold exec. rewrite Hv. reflexivity.
Qed.

Lemma exec_safe {A} I (m : M A) :
  Safe I m -> forall s a s', I (regs s) -> exec m s = Some (a, s') -> I (regs s').
Proof.
  intros H s a s' HI He. destruct (H _ HI) as (a0 & rs0 & Hv & HI0).
  unfold exec in He. rewrite Hv in He. injection He as <- <-. exact HI0.
Qed.

(** * Rules *)

Lemma Safe_return {A} I (a : A) : Safe I (returnM a).
Proof. intros rs H. exists a, rs. split; [reflexivity | exact H]. Qed.

Lemma Safe_read I r : Safe I (read_reg r).
Proof. intros rs H. eexists _, rs. split; [reflexivity | exact H]. Qed.

Lemma Safe_write I r v : (forall rs, I rs -> I (register_set r v rs)) -> Safe I (write_reg r v).
Proof. intros HI rs H. eexists _, _. split; [reflexivity | apply HI, H]. Qed.

Lemma Safe_bind {A B} I (m : M A) (f : A -> M B) :
  Safe I m -> (forall a, Safe I (f a)) -> Safe I (m >>= f).
Proof.
  intros Hm Hf rs H. rewrite eval_bind.
  destruct (Hm rs H) as (a & rs' & -> & H'). apply Hf, H'.
Qed.

Lemma Safe_bind0 {B} I (m : M unit) (n : M B) : Safe I m -> Safe I n -> Safe I (m >> n).
Proof.
  intros Hm Hn rs H. rewrite eval_bind0.
  destruct (Hm rs H) as (a & rs' & -> & H'). apply Hn, H'.
Qed.

Lemma Safe_if {A} I (b : bool) (m n : M A) : Safe I m -> Safe I n -> Safe I (if b then m else n).
Proof. destruct b; auto. Qed.

(** [step]'s decoding: a word that decodes runs [f] on its instruction, and any other runs [n]. *)
Lemma Safe_decode {A} I w (f : instruction -> M A) (n : M A) :
  (forall i, Safe I (f i)) -> Safe I n ->
  Safe I (encdec_backwards_matches w >>= fun b => if b then encdec_backwards w >>= f else n).
Proof.
  intros Hf Hn rs H. rewrite eval_bind, encdec_backwards_matches_decode.
  destruct (decode w) as [i|] eqn:Hd; cbn [eval returnM returnm]; [|apply Hn, H].
  rewrite eval_bind, (encdec_backwards_decode w i Hd). apply Hf, H.
Qed.

(** Lemmas about whole actions, which [safe] uses instead of opening them up. *)
Create HintDb safe_actions.

(** Facts that discharge a write's side condition: a write must keep the invariant. *)
Create HintDb safe_writes.
#[export] Hint Extern 1 (register_beq _ _ = false) => reflexivity : safe_writes.
#[export] Hint Extern 1 True => exact I : safe_writes.

(** The model's own actions, which [safe] opens up on demand. *)
Ltac unfold_actions :=
  unfold step, run_instruction, retire, reset, rX, wX, read_byte, write_byte, read_word, write_word,
    execute_NOP, execute_HLT, execute_MOV, execute_LIL, execute_LIH, execute_LDW, execute_STW,
    execute_LDB, execute_STB, execute_ADD, execute_SUB, execute_ADDI, execute_MUL, execute_AND,
    execute_OR, execute_XOR, execute_NOT, execute_SHL, execute_SHR, execute_SLT, execute_BZ,
    execute_BN, execute_JMP, execute_CALL, execute_RET, execute_PUSH, execute_POP.

(** Prove [Safe I m] by taking [m] apart. Register writes need their side condition from the
    hint database [safe_writes]. A register read is matched on its register: its result type may
    be written as [mword 16] rather than [type_of_register PC], which [apply] cannot unify. *)
Ltac safe :=
  repeat first
    [ progress cbv beta zeta
    | lazymatch goal with |- forall _, _ => intro end
    | apply Safe_bind0 | apply Safe_decode | apply Safe_bind | apply Safe_if | apply Safe_return
    | lazymatch goal with |- Safe _ (read_reg ?r) => exact (Safe_read _ r) end
    | lazymatch goal with
      | |- Safe _ (@write_reg _ _ _) =>
          apply Safe_write; intros; cbv beta in *; solve [eauto with safe_writes]
      end
    | solve [eauto with safe_actions]
    | unfold_actions ].

(** The instruction [execute] is applied to, taken apart one constructor at a time. *)
Ltac destruct_instruction i :=
  destruct i; repeat match goal with
    | p : (_ * _)%type |- _ => destruct p
    | u : unit |- _ => destruct u
    end; cbn [execute].
