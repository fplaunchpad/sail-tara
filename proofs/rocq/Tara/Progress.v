(** Progress: the model's actions always complete.

    From every machine and every setting of the input lines, [step], [run_instruction] and [reset]
    run to completion with exactly one outcome. They never fail, assert, throw or make a choice.
    The generated code only reads and writes registers, and every operation on words is a total
    function, so nothing can go wrong; the proof checks that structure for each instruction. *)
From stdpp Require Import base.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara Machine Logic.

Lemma execute_total i : Total (execute i).
Proof. destruct_instruction i. all: safe. Qed.
#[local] Hint Resolve execute_total : safe_actions.

Lemma step_total keys : Total (step keys).
Proof. safe. Qed.

Lemma run_instruction_total keys i : Total (run_instruction keys i).
Proof. safe. Qed.

Lemma reset_total : Total (reset tt).
Proof. safe. Qed.

(** [step] completes from every machine and every setting of the input lines. *)
Theorem step_progress keys s : exists r s', exec (step keys) s = Some (r, s').
Proof. apply (exec_total _ (step_total keys)). Qed.

(** In Sail's own terms: whatever the choice source, [step] has the same single outcome, a value
    and a machine, and it leaves the choice source as it found it. *)
Theorem step_one_outcome keys s :
  exists r s', forall cs, liftState register_accessors (step keys) s cs = [(Value r, s', cs)].
Proof.
  destruct (step_progress keys s) as (r & s' & H). exists r, s'. exact (exec_sound _ _ _ _ H).
Qed.

(** Running a decoded instruction completes. *)
Theorem run_instruction_progress keys i s :
  exists r s', exec (run_instruction keys i) s = Some (r, s').
Proof. apply (exec_total _ (run_instruction_total keys i)). Qed.

(** [reset] completes. *)
Theorem reset_progress s : exists u s', exec (reset tt) s = Some (u, s').
Proof. apply (exec_total _ reset_total). Qed.

(** * Fetching *)

(** Reading a word changes no register. *)
Lemma read_word_pure addr rs : exists raw, eval (read_word addr) rs = Some (raw, rs).
Proof.
  assert (H : Safe (fun rs' => rs' = rs) (read_word addr)) by safe.
  destruct (H rs eq_refl) as (raw & rs' & Hv & ->). eauto.
Qed.

(** What [fetch] returns is what [read_word] gives, at the PC of the registers with KEYS written. *)
Lemma fetch_eval keys s raw :
  fetch keys s = Some raw <->
  eval (read_word (register_lookup PC (register_set KEYS keys (regs s))))
       (register_set KEYS keys (regs s)) = Some (raw, register_set KEYS keys (regs s)).
Proof.
  destruct (read_word_pure (register_lookup PC (register_set KEYS keys (regs s)))
              (register_set KEYS keys (regs s))) as [raw0 Hr].
  unfold fetch, exec, pc. cbn. rewrite Hr. cbn. split; congruence.
Qed.

(** Fetching always yields a word. *)
Theorem fetch_progress keys s : exists raw, fetch keys s = Some raw.
Proof.
  destruct (read_word_pure (register_lookup PC (register_set KEYS keys (regs s)))
              (register_set KEYS keys (regs s))) as [raw Hr].
  exists raw. apply fetch_eval, Hr.
Qed.
