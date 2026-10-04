(** Frame conditions: what running an instruction leaves alone.

    Only STW, STB and PUSH change memory. Only HLT sets HALTED. Every instruction except the
    branches BZ, BN, JMP, CALL and RET retires with PC advanced to the next word, wrapping at
    0x800. [run_instruction] executes an instruction as if it had been fetched from PC, and [step]
    is a fetch followed by [run_instruction], so the facts hold for both. *)
From Stdlib Require Import ZArith.
From stdpp Require Import base.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara Machine Logic PcMask Progress Decode Step Halted.
Open Scope Z_scope.

(** * Instruction classes *)

Definition writes_memory (i : instruction) : bool :=
  match i with STW _ | STB _ | PUSH _ => true | _ => false end.

Definition halts (i : instruction) : bool :=
  match i with HLT _ => true | _ => false end.

(** The instructions that may set the next PC to something other than PC + 2. *)
Definition redirects (i : instruction) : bool :=
  match i with BZ _ | BN _ | JMP _ | CALL _ | RET _ => true | _ => false end.

(** * What an instruction keeps *)

(** A register is kept by [m] when it holds the same value in every state that [m] ends in: [Safe]
    with the invariant that the register holds a given value. A write to another register keeps
    it, and [execute] writes only to the registers that the instruction is meant to change. *)
Lemma keeps_write r r' v c :
  register_beq r r' = false -> forall rs, register_lookup r rs = c ->
  register_lookup r (register_set r' v rs) = c.
Proof. intros H rs E. rewrite irrelevant_register_set by exact H. exact E. Qed.
#[local] Hint Resolve keeps_write : safe_writes.

Lemma execute_keeps_mem i :
  writes_memory i = false -> forall c, Safe (fun rs => register_lookup MEM rs = c) (execute i).
Proof. intros H c. destruct_instruction i; try (simpl in H; discriminate). all: safe. Qed.

Lemma execute_keeps_halted i :
  halts i = false -> forall c, Safe (fun rs => register_lookup HALTED rs = c) (execute i).
Proof. intros H c. destruct_instruction i; try (simpl in H; discriminate). all: safe. Qed.

Lemma execute_keeps_next_pc i :
  redirects i = false -> forall c, Safe (fun rs => register_lookup nextPC rs = c) (execute i).
Proof. intros H c. destruct_instruction i; try (simpl in H; discriminate). all: safe. Qed.

#[local] Hint Resolve execute_keeps_mem execute_keeps_halted : safe_actions.

(** [run_instruction] adds writes to KEYS, nextPC and PC, and nothing else. *)
Lemma run_instruction_keeps_mem keys i :
  writes_memory i = false -> forall c,
  Safe (fun rs => register_lookup MEM rs = c) (run_instruction keys i).
Proof. intros H c. unfold run_instruction. safe. Qed.

Lemma run_instruction_keeps_halted keys i :
  halts i = false -> forall c,
  Safe (fun rs => register_lookup HALTED rs = c) (run_instruction keys i).
Proof. intros H c. unfold run_instruction. safe. Qed.

(** * Memory *)

(** Running an instruction other than STW, STB and PUSH leaves memory as it was. *)
Theorem only_stores_change_memory keys i s r s' :
  exec (run_instruction keys i) s = Some (r, s') -> writes_memory i = false -> mem s' = mem s.
Proof.
  intros He H.
  exact (exec_safe _ _ (run_instruction_keeps_mem keys i H (mem s)) s r s' eq_refl He).
Qed.

(** * HALTED *)

(** Running an instruction other than HLT leaves HALTED as it was. *)
Theorem only_hlt_changes_halted keys i s r s' :
  exec (run_instruction keys i) s = Some (r, s') -> halts i = false -> halted s' = halted s.
Proof.
  intros He H.
  exact (exec_safe _ _ (run_instruction_keeps_halted keys i H (halted s)) s r s' eq_refl He).
Qed.

Lemma retire_hlt_eval rs :
  exists rs', eval (retire (HLT tt)) rs = Some (Retired tt, rs') /\
    register_lookup HALTED rs' = true.
Proof.
  unfold retire. cbn [execute execute_HLT]. eval_simp.
  eexists. split; [reflexivity|]. lookup_simp. reflexivity.
Qed.

(** Running HLT leaves the CPU halted. *)
Theorem hlt_halts keys s r s' :
  exec (run_instruction keys (HLT tt)) s = Some (r, s') -> halted s' = true.
Proof.
  intros He. destruct (halted s) eqn:Hh.
  - rewrite (halted_run_instruction keys _ s Hh) in He. injection He as <- <-. exact Hh.
  - unfold exec in He. rewrite (run_instruction_eval keys _ _ Hh) in He.
    destruct (retire_hlt_eval (register_set KEYS keys (regs s))) as (rs' & Hv & Hr).
    rewrite Hv in He. injection He as <- <-. exact Hr.
Qed.

(** * PC *)

(** An instruction that is not a branch leaves the next PC at PC + 2, so [retire] masks that. *)
Lemma retire_sequential_eval i rs :
  redirects i = false ->
  exists rs', eval (retire i) rs = Some (Retired tt, rs') /\
    register_lookup PC rs' = pc_mask (add_vec (register_lookup PC rs) (Ox"0002")).
Proof.
  intros H.
  destruct (execute_keeps_next_pc i H
      (register_lookup nextPC (register_set nextPC (add_vec (register_lookup PC rs) (Ox"0002")) rs))
      (register_set nextPC (add_vec (register_lookup PC rs) (Ox"0002")) rs) eq_refl)
    as ([] & rs2 & Hx & Hn).
  exists (register_set PC (pc_mask (register_lookup nextPC rs2)) rs2). split.
  - unfold retire. eval_simp. rewrite Hx. eval_simp. reflexivity.
  - rewrite register_lookup_set, Hn, register_lookup_set. reflexivity.
Qed.

(** Running an instruction that is not a branch retires it and moves PC to the next word, wrapping
    at 0x800. *)
Theorem non_branches_advance_pc keys i s r s' :
  exec (run_instruction keys i) s = Some (r, s') -> halted s = false -> redirects i = false ->
  r = Retired tt /\ uint (pc s') = (uint (pc s) + 2) mod 2048.
Proof.
  intros He Hh Hr. unfold exec in He. rewrite (run_instruction_eval keys i _ Hh) in He.
  destruct (retire_sequential_eval i (register_set KEYS keys (regs s)) Hr) as (rs' & Hv & Hpc).
  rewrite Hv in He. injection He as <- <-. split; [reflexivity|].
  unfold pc, regs, with_regs in *. cbn [ss_regstate] in *. rewrite Hpc. lookup_simp.
  apply pc_mask_add2.
Qed.

(** * Stepping *)

(** When the fetched word decodes to an instruction, [step] runs that instruction, so everything
    above holds of [step] too. *)
Theorem step_runs_instruction keys s raw i :
  halted s = false -> fetch keys s = Some raw -> decode raw = Some i ->
  exec (step keys) s = exec (run_instruction keys i) s.
Proof.
  intros Hh Hf Hd. pose proof (proj1 (fetch_eval keys s raw) Hf) as Hr. unfold exec.
  rewrite (step_retire_eval keys (regs s) raw i Hh Hr Hd).
  rewrite (run_instruction_eval keys i (regs s) Hh). reflexivity.
Qed.

Print Assumptions only_stores_change_memory.
Print Assumptions only_hlt_changes_halted.
Print Assumptions hlt_halts.
Print Assumptions non_branches_advance_pc.
Print Assumptions step_runs_instruction.
