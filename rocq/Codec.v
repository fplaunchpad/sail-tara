(** The instruction codec round-trips: decoding an encoded instruction gives the instruction back.

    [encode] only documents the encodings and no model function calls it, so this theorem is its
    test. The proof is by exhaustion: operands are at most 11 bits wide, so each constructor has
    at most 2048 values, and [vm_compute] decides all of the 30355 instructions. *)
From Stdlib Require Import ZArith.
From stdpp Require Import base finite bitvector.definitions.
Require Import SailStdpp.Base.
From Tara Require Import Tara_types Tara.

(** Operands are 3 (register), 5, 8 or 11 bits wide; [bv_finite] lists all their values. *)
#[local] Instance Finite_mword3 : Finite (mword 3) := bv_finite 3.
#[local] Instance Finite_mword5 : Finite (mword 5) := bv_finite 5.
#[local] Instance Finite_mword8 : Finite (mword 8) := bv_finite 8.
#[local] Instance Finite_mword11 : Finite (mword 11) := bv_finite 11.

(** Let instance search see through the model's aliases, as in [regidx * bits 8]. *)
#[local] Typeclasses Transparent regidx bits.

(** [Tara.encode] and [Tara.decode] are the generated functions; stdpp's [Countable] class has
    methods of the same names. Each case reverts the constructor's operands and checks every
    value of them. *)
Theorem instruction_roundtrip : forall i : instruction, Tara.decode (Tara.encode i) = Some i.
Proof.
  intros i; destruct i;
    match goal with x : _ |- _ => revert x end;
    refine (bool_decide_unpack _ _); vm_compute; reflexivity.
Qed.

Print Assumptions instruction_roundtrip.
