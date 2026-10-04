(** Unassigned opcodes.

    The opcode of a word is its top five bits. Opcodes 0 to 26 are instructions and 27 to 31 are
    not: [decode] fails on exactly those, and when [step] fetches such a word it returns [Illegal]
    with the word, advances PC to the next word and changes nothing else but the input lines. *)
From Stdlib Require Import ZArith.
From stdpp Require Import base finite bitvector.definitions.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara Machine Logic PcMask Progress Step Halted.
Open Scope Z_scope.

Definition opcode (w : mword 16) : Z := uint (subrange_vec_dec w 15 11).

(** * Decoding *)

(** [decode] only looks at the opcode to tell whether the word is an instruction, so the proof
    abstracts the opcode and checks its 32 values. *)
Lemma decode_is_none w : is_none (decode w) = Z.leb 27 (opcode w).
Proof.
  unfold decode, opcode. generalize (subrange_vec_dec w 15 11) as op.
  refine (fun op : mword 5 => _). revert op.
  refine (bool_decide_unpack _ _); vm_compute; reflexivity.
Qed.

(** A word fails to decode exactly when its opcode is 27 or more, for all 65536 words. *)
Theorem decode_none_iff w : decode w = None <-> 27 <= opcode w.
Proof.
  pose proof (decode_is_none w) as H. destruct (decode w); simpl in H; split; intros G.
  - discriminate.
  - symmetry in H. apply Z.leb_nle in H. contradiction.
  - apply Z.leb_le. symmetry. exact H.
  - reflexivity.
Qed.

(** * Fetching an unassigned word *)

(** When the fetched word does not decode, [step] returns [Illegal] with that word. PC moves on to
    the next word, wrapping at 0x800, and the input lines are set to [keys]. Nothing else changes:
    R0 to R7, the memory, the halt latch and the next PC are as they were, and so is everything in
    the machine but its registers. *)
Theorem step_illegal keys s raw :
  halted s = false -> fetch keys s = Some raw -> decode raw = None ->
  exists s', exec (step keys) s = Some (Illegal raw, s') /\
    s' = with_regs s (regs s') /\
    uint (pc s') = (uint (pc s) + 2) mod 2048 /\ lines s' = keys /\
    gpr s' = gpr s /\ mem s' = mem s /\ halted s' = halted s /\ next_pc s' = next_pc s.
Proof.
  intros Hh Hf Hd. pose proof (proj1 (fetch_eval keys s raw) Hf) as Hr.
  set (rs1 := register_set KEYS keys (regs s)) in *.
  set (rs2 := register_set PC (pc_mask (add_vec (register_lookup PC rs1) (Ox"0002"))) rs1).
  exists (with_regs s rs2). repeat split.
  - unfold exec. rewrite (step_illegal_eval keys (regs s) raw Hh Hr Hd). reflexivity.
  - unfold pc, regs, with_regs in *. cbn. subst rs2 rs1. lookup_simp.
    rewrite pc_mask_add2. reflexivity.
  - unfold lines, regs, with_regs. cbn. subst rs2 rs1. lookup_simp. reflexivity.
  - unfold gpr, regs, with_regs. cbn. subst rs2 rs1. lookup_simp. reflexivity.
  - unfold mem, regs, with_regs. cbn. subst rs2 rs1. lookup_simp. reflexivity.
  - unfold halted, regs, with_regs. cbn. subst rs2 rs1. lookup_simp. reflexivity.
  - unfold next_pc, regs, with_regs. cbn. subst rs2 rs1. lookup_simp. reflexivity.
Qed.

(** And only then: [Illegal] comes from a running CPU that fetched a word it cannot decode. *)
Theorem illegal_only keys s raw s' :
  exec (step keys) s = Some (Illegal raw, s') ->
  halted s = false /\ fetch keys s = Some raw /\ decode raw = None.
Proof.
  intros He. destruct (halted s) eqn:Hh.
  - rewrite (halted_step keys s Hh) in He. discriminate.
  - destruct (fetch_progress keys s) as (raw0 & Hf).
    pose proof (proj1 (fetch_eval keys s raw0) Hf) as Hr.
    destruct (decode raw0) as [i|] eqn:Hd.
    + unfold exec in He. rewrite (step_retire_eval keys (regs s) raw0 i Hh Hr Hd) in He.
      destruct (retire_returns i (register_set KEYS keys (regs s))) as (rs' & Hv).
      rewrite Hv in He. discriminate.
    + destruct (step_illegal keys s raw0 Hh Hf Hd) as (s'' & He' & _).
      rewrite He in He'. injection He' as <- _. auto.
Qed.

Print Assumptions decode_none_iff.
Print Assumptions step_illegal.
Print Assumptions illegal_only.
