(** Decoding as a function.

    Sail generates [encdec_backwards_matches] and [encdec_backwards] as actions, because
    [encdec_backwards] fails on a word that no clause of [encdec] matches. Neither touches the
    machine, so each one either returns at once or fails. [decode] reads what they return, and the
    theorems about [step] are stated with it. *)
From stdpp Require Import base finite bitvector.definitions.
Require Import SailStdpp.Base.
From Tara Require Import Tara_types Tara.

(** The instruction a word decodes to, if [encdec] has a clause that matches it. *)
Definition decode (w : mword 16) : option instruction :=
  match encdec_backwards_matches w, encdec_backwards w with
  | Done true, Done i => Some i
  | _, _ => None
  end.

(** Every word is either matched and decoded, or not matched. Only the opcode decides which, so
    the proof abstracts it and checks its 32 values. *)
Lemma encdec_backwards_returns w :
  match encdec_backwards_matches w, encdec_backwards w with
  | Done true, Done _ | Done false, _ => true
  | _, _ => false
  end = true.
Proof.
  unfold encdec_backwards_matches, encdec_backwards. cbv beta zeta.
  generalize (subrange_vec_dec w 15 11) as op.
  refine (fun op : mword 5 => _). revert op.
  refine (bool_decide_unpack _ _); vm_compute; reflexivity.
Qed.

(** So [step]'s test of a word returns whether it decodes, ... *)
Lemma encdec_backwards_matches_decode w :
  encdec_backwards_matches w = returnM (if decode w is Some _ then true else false).
Proof.
  pose proof (encdec_backwards_returns w) as H. unfold decode in *.
  destruct (encdec_backwards_matches w); try discriminate.
  match goal with b : bool |- _ => destruct b end;
    destruct (encdec_backwards w); try discriminate; reflexivity.
Qed.

(** ... and a word that decodes is decoded to that instruction. *)
Lemma encdec_backwards_decode w i : decode w = Some i -> encdec_backwards w = returnM i.
Proof.
  unfold decode. destruct (encdec_backwards_matches w); try discriminate.
  match goal with b : bool |- _ => destruct b end;
    destruct (encdec_backwards w); try discriminate. now intros [= ->].
Qed.
