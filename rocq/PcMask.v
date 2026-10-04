(** The PC wraps at 0x800.

    Every write to PC goes through [pc_mask], which keeps the low eleven bits of a word. So the
    result is below 0x800, and the successor [pc_mask (PC + 2)] is [(PC + 2) mod 2048]. *)
From Stdlib Require Import ZArith Lia.
From stdpp Require Import base bitvector.definitions.
Require Import SailStdpp.Base.
From Tara Require Import Tara_types Tara.
Open Scope Z_scope.

(** [lia] would otherwise write a cache file into the directory it is run from. *)
Local Unset Lia Cache.

(** The Sail library's casts between sizes compute away when the sizes are numerals, so for these
    sizes its operations are stdpp's bitvector operations, by [reflexivity]. *)
Lemma pc_mask_bv (v : mword 16) :
  pc_mask v = bv_concat 16 (Z_to_bv 5 0) (bv_extract 0 11 v).
Proof. reflexivity. Qed.

Lemma add2_bv (v : mword 16) : add_vec v (Ox"0002") = bv_add v (Z_to_bv 16 2).
Proof. reflexivity. Qed.

Lemma uint_bv {a} (x : mword a) : uint x = bv_unsigned x.
Proof.
  unfold uint, MachineWord.MachineWord.word_to_N. rewrite Z2N.id; [reflexivity|].
  exact (proj1 (bv_unsigned_in_range _ x)).
Qed.

(** [pc_mask] keeps the low eleven bits. *)
Lemma uint_pc_mask (v : mword 16) : uint (pc_mask v) = uint v mod 2048.
Proof.
  rewrite !uint_bv, pc_mask_bv, bv_concat_unsigned', bv_extract_unsigned.
  rewrite Z_to_bv_unsigned. unfold bv_wrap, bv_modulus. simpl.
  rewrite Z.shiftr_0_r, Z.shiftl_0_l, Z.lor_0_l.
  assert (Hb := Z.mod_pos_bound (bv_unsigned v) 2048 ltac:(lia)).
  apply Z.mod_small. lia.
Qed.

Lemma pc_mask_lt (v : mword 16) : uint (pc_mask v) < 2048.
Proof. rewrite uint_pc_mask. apply Z.mod_pos_bound. lia. Qed.

Lemma uint_add2 (v : mword 16) : uint (add_vec v (Ox"0002")) = (uint v + 2) mod 65536.
Proof.
  rewrite add2_bv, !uint_bv, bv_add_unsigned, Z_to_bv_unsigned. unfold bv_wrap, bv_modulus. simpl.
  assert (E : 2 ^ 16 = 65536) by reflexivity. rewrite E. lia.
Qed.

(** The PC advance wraps at 2048, for every PC. *)
Lemma pc_mask_add2 (v : mword 16) : uint (pc_mask (add_vec v (Ox"0002"))) = (uint v + 2) mod 2048.
Proof. rewrite uint_pc_mask, uint_add2. lia. Qed.
