(** Unassigned opcodes.

    The opcode of a word is its top five bits. Opcodes 0 to 26 are instructions and 27 to 31 are
    not: [decode] fails on exactly those, and when [step] fetches such a word it returns [Illegal]
    with the word, advances PC to the next word and changes nothing else but the input lines. *)
From Stdlib Require Import ZArith.
From stdpp Require Import base finite bitvector.definitions.
Require Import SailStdpp.Base SailStdpp.State_monad SailStdpp.State_lifting.
From Tara Require Import Tara_types Tara Machine Logic PcMask Progress Decode Step Halted.
Open Scope Z_scope.

Definition opcode (w : mword 16) : Z := uint (subrange_vec_dec w 15 11).

(** * Decoding *)

Lemma decode_is_none w : is_none (decode w) = Z.leb 27 (opcode w).
Proof. unfold decode, opcode, encdec_backwards_matches, encdec_backwards. by_opcode w. Qed.

(** A word fails to decode exactly when its opcode is 27 or more, for all 65536 words. *)
Theorem decode_none_iff w : decode w = None <-> 27 <= opcode w.
Proof.
  rewrite <- Z.leb_le, <- decode_is_none. destruct (decode w); cbn; split; congruence.
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
  intros Hh Hf Hd. apply fetch_eval in Hf.
  eexists. split; [unfold exec; rewrite (step_illegal_eval keys (regs s) raw Hh Hf Hd); done|].
  unfold pc, lines, gpr, mem, halted, next_pc, regs. cbn [with_regs ss_regstate]. lookup_simp.
  rewrite pc_mask_add2. repeat split.
Qed.

(** And only then: [Illegal] comes from a running CPU that fetched a word it cannot decode. *)
Theorem illegal_only keys s raw s' :
  exec (step keys) s = Some (Illegal raw, s') ->
  halted s = false /\ fetch keys s = Some raw /\ decode raw = None.
Proof.
  intros He. destruct (halted s) eqn:Hh.
  { rewrite (halted_step keys s Hh) in He. discriminate. }
  destruct (fetch_progress keys s) as (raw0 & Hf).
  destruct (decode raw0) as [i|] eqn:Hd.
  - apply fetch_eval in Hf. unfold exec in He.
    rewrite (step_retire_eval keys (regs s) raw0 i Hh Hf Hd) in He.
    destruct (retire_returns i (register_set KEYS keys (regs s))) as [rs' Hv].
    rewrite Hv in He. discriminate.
  - destruct (step_illegal keys s raw0 Hh Hf Hd) as (s'' & He' & _).
    rewrite He in He'. injection He' as <- _. auto.
Qed.
