(** The cases of [step], in register terms.

    [step] reads HALTED: a halted CPU stops and does nothing else. Otherwise it writes KEYS, fetches
    the word at PC and decodes it. A word that decodes is an instruction, which is retired like one
    run by [run_instruction]; any other word is illegal, and only PC moves on. These equations are
    what the theorems about [step] are built from. *)
From stdpp Require Import base.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara Machine Logic PcMask Progress.

(** A halted CPU stops, unchanged. *)
Lemma step_halted_eval keys rs :
  register_lookup HALTED rs = true -> eval (step keys) rs = Some (Stopped tt, rs).
Proof. intros H. unfold step. eval_simp. rewrite H. reflexivity. Qed.

Lemma run_instruction_halted_eval keys i rs :
  register_lookup HALTED rs = true -> eval (run_instruction keys i) rs = Some (Stopped tt, rs).
Proof. intros H. unfold run_instruction. eval_simp. rewrite H. reflexivity. Qed.

(** A running CPU retires the instruction once KEYS is written. *)
Lemma run_instruction_eval keys i rs :
  register_lookup HALTED rs = false ->
  eval (run_instruction keys i) rs = eval (retire i) (register_set KEYS keys rs).
Proof.
  intros H. unfold run_instruction. eval_simp. rewrite H. cbn iota. eval_simp. reflexivity.
Qed.

(** A word that decodes is retired as its instruction. *)
Lemma step_retire_eval keys rs raw i :
  register_lookup HALTED rs = false ->
  eval (read_word (register_lookup PC (register_set KEYS keys rs))) (register_set KEYS keys rs)
    = Some (raw, register_set KEYS keys rs) ->
  decode raw = Some i ->
  eval (step keys) rs = eval (retire i) (register_set KEYS keys rs).
Proof.
  intros Hh Hr Hd. unfold step. eval_simp. rewrite Hh. cbn iota. eval_simp.
  rewrite Hr, Hd. cbn iota. reflexivity.
Qed.

(** Retiring always completes with [Retired]. *)
Lemma retire_returns i rs : exists rs', eval (retire i) rs = Some (Retired tt, rs').
Proof.
  destruct (execute_total i (register_set nextPC (add_vec (register_lookup PC rs) (Ox"0002")) rs)
              I) as (u & rs2 & Hx & _).
  unfold retire. eval_simp. rewrite Hx. eval_simp. eauto.
Qed.

(** A word that does not decode is illegal: KEYS, then PC. *)
Lemma step_illegal_eval keys rs raw :
  register_lookup HALTED rs = false ->
  eval (read_word (register_lookup PC (register_set KEYS keys rs))) (register_set KEYS keys rs)
    = Some (raw, register_set KEYS keys rs) ->
  decode raw = None ->
  eval (step keys) rs = Some (Illegal raw,
    register_set PC (pc_mask (add_vec (register_lookup PC (register_set KEYS keys rs)) (Ox"0002")))
      (register_set KEYS keys rs)).
Proof.
  intros Hh Hr Hd. unfold step. eval_simp. rewrite Hh. cbn iota. eval_simp.
  rewrite Hr, Hd. eval_simp. reflexivity.
Qed.
