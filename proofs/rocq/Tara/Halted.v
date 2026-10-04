(** Halting is absorbing.

    A halted CPU does nothing until reset: [step] and [run_instruction] return [Stopped] and leave
    the machine exactly as it was, so the next step finds it halted again. *)
From stdpp Require Import base.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara Machine Logic Progress Step.

Lemma with_regs_regs s : with_regs s (regs s) = s.
Proof. destruct s; reflexivity. Qed.

(** When HALTED is set, [step] returns [Stopped] and the machine is unchanged. *)
Theorem halted_step keys s : halted s = true -> exec (step keys) s = Some (Stopped tt, s).
Proof.
  intros H. unfold exec. rewrite (step_halted_eval keys (regs s) H). cbn.
  rewrite with_regs_regs. reflexivity.
Qed.

(** So does running an instruction directly. *)
Theorem halted_run_instruction keys i s :
  halted s = true -> exec (run_instruction keys i) s = Some (Stopped tt, s).
Proof.
  intros H. unfold exec. rewrite (run_instruction_halted_eval keys i (regs s) H). cbn.
  rewrite with_regs_regs. reflexivity.
Qed.

Print Assumptions halted_step.
Print Assumptions halted_run_instruction.
