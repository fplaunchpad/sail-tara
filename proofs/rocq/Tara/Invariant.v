(** The machine invariant: PC stays below 0x800.

    PC is 16 bits wide, but the model keeps only its low eleven bits, because every write to PC
    goes through [pc_mask]. So a machine is well formed, [wf], when the upper five bits of PC are
    zero. A step that retires an instruction or stops on an unassigned opcode writes a masked PC
    whatever PC was before; a halted machine does nothing and keeps the PC it had. Reset and
    power-on start from a well-formed machine. *)
From Stdlib Require Import ZArith.
From stdpp Require Import base.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara Machine Logic PcMask Progress Decode Step.
Open Scope Z_scope.

(** A register record is well formed when PC is below 0x800, and a machine is when its registers
    are. The proofs work with register records. *)
Definition wf_rs (rs : regstate) : Prop := uint (register_lookup PC rs) < 0x800.

Definition wf (s : machine) : Prop := wf_rs (regs s).

Lemma wf_write_pc v : uint v < 0x800 -> forall rs, wf_rs (register_set PC v rs).
Proof. intros H rs. unfold wf_rs. rewrite register_lookup_set. exact H. Qed.

Lemma wf_write_pc_mask w rs : wf_rs (register_set PC (pc_mask w) rs).
Proof. apply wf_write_pc, pc_mask_lt. Qed.

Lemma wf_write_other r v :
  register_beq PC r = false -> forall rs, wf_rs rs -> wf_rs (register_set r v rs).
Proof. intros H rs. unfold wf_rs. rewrite irrelevant_register_set; auto. Qed.

#[local] Hint Resolve wf_write_pc wf_write_pc_mask wf_write_other : safe_writes.
#[local] Hint Extern 1 (uint _ < _) => vm_compute; reflexivity : safe_writes.

Lemma execute_wf i : Safe wf_rs (execute i).
Proof. destruct_instruction i. all: safe. Qed.
#[local] Hint Resolve execute_wf : safe_actions.

Lemma step_wf keys : Safe wf_rs (step keys).
Proof. safe. Qed.

Lemma run_instruction_wf keys i : Safe wf_rs (run_instruction keys i).
Proof. safe. Qed.

(** If PC is below 0x800 before a step, it is below 0x800 after it, whatever the step returns. *)
Theorem step_preserves_wf keys s r s' :
  wf s -> exec (step keys) s = Some (r, s') -> wf s'.
Proof. apply exec_safe, step_wf. Qed.

(** The same for running an instruction directly. *)
Theorem run_instruction_preserves_wf keys i s r s' :
  wf s -> exec (run_instruction keys i) s = Some (r, s') -> wf s'.
Proof. apply exec_safe, run_instruction_wf. Qed.

(** A running machine masks PC in every step, so it does not need to be well formed before. *)
Lemma step_masks_pc_eval keys rs :
  register_lookup HALTED rs = false ->
  exists a rs', eval (step keys) rs = Some (a, rs') /\ wf_rs rs'.
Proof.
  intros Hh.
  destruct (read_word_pure (register_lookup PC (register_set KEYS keys rs))
              (register_set KEYS keys rs)) as [raw Hr].
  destruct (decode raw) as [i|] eqn:Hd.
  - rewrite (step_retire_eval keys rs raw i Hh Hr Hd).
    destruct (retire_returns i (register_set KEYS keys rs)) as [rs' ->].
    eauto using wf_write_pc_mask.
  - rewrite (step_illegal_eval keys rs raw Hh Hr Hd). eauto using wf_write_pc_mask.
Qed.

(** A step of a running machine leaves PC below 0x800 even if it was not before. *)
Theorem step_masks_pc keys s r s' :
  halted s = false -> exec (step keys) s = Some (r, s') -> wf s'.
Proof.
  intros Hh He. unfold exec in He.
  destruct (step_masks_pc_eval keys (regs s) Hh) as (a & rs' & Hv & Hw).
  rewrite Hv in He. injection He as <- <-. exact Hw.
Qed.

Lemma reset_eval rs :
  eval (reset tt) rs = Some (tt, register_set HALTED false (register_set PC (Ox"0000") rs)).
Proof. unfold reset. eval_simp. reflexivity. Qed.

(** Reset leaves PC at 0 and the CPU running, from any machine at all. *)
Theorem reset_establishes_wf s u s' :
  exec (reset tt) s = Some (u, s') -> wf s' /\ halted s' = false.
Proof.
  unfold exec. rewrite reset_eval. intros [= <- <-].
  unfold wf, wf_rs, halted, regs. cbn [ss_regstate with_regs]. lookup_simp.
  split; [vm_compute|]; reflexivity.
Qed.

(** Resetting the generated default register record yields a well-formed, running machine. *)
Theorem power_on_wf s : power_on = Some s -> wf s /\ halted s = false.
Proof.
  unfold power_on. destruct (exec (reset tt) (init_state init_regstate)) as [[u s0]|] eqn:E;
    cbn; [|discriminate].
  intros [= <-]. exact (reset_establishes_wf _ _ _ E).
Qed.
