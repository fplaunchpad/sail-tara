(** Smoke test: the generated model runs, and the hardware manual's Fibonacci program ends in the
    documented state. The expected states are checked by computation, so compiling this file is
    the test. *)
From Stdlib Require Import List ZArith.
From stdpp Require Import base.
Require Import SailStdpp.Base.
From Tara Require Import Tara_types Tara Run.
Import ListNotations.
Open Scope Z_scope.

(** The model leaves its registers undefined; the default choice makes them zero. *)
Example power_on_state :
  option_map observe power_on =
    Some {| pc := 0; gpr := [0; 0; 0; 0; 0; 0; 0; 0]; halted := false |}.
Proof. vm_compute. reflexivity. Qed.

(** An instruction run directly takes effect as if fetched from PC, which then moves on by 2. *)
Example run_instruction_lil :
  option_map observe (
    s ← power_on;
    after (run_instruction no_keys (LIL ('b"010", Ox"05"))) s) =
    Some {| pc := 2; gpr := [0; 0; 5; 0; 0; 0; 0; 0]; halted := false |}.
Proof. vm_compute. reflexivity. Qed.

(** R2 and R3 walk the Fibonacci numbers while R5 counts down from 10; R6 receives the result. *)
Definition fibonacci : list (mword 16) := [
  Ox"1a00"; (* 0x00  LIL R2, 0 *)
  Ox"1b01"; (* 0x02  LIL R3, 1 *)
  Ox"1d0a"; (* 0x04  LIL R5, 10 *)
  Ox"a505"; (* 0x06  BZ R5, 5, to 0x12 *)
  Ox"4c4c"; (* 0x08  ADD R4, R2, R3 *)
  Ox"1260"; (* 0x0a  MOV R2, R3 *)
  Ox"1380"; (* 0x0c  MOV R3, R4 *)
  Ox"5dff"; (* 0x0e  ADDI R5, -1 *)
  Ox"b7fa"; (* 0x10  JMP -6, to 0x06 *)
  Ox"1640"; (* 0x12  MOV R6, R2 *)
  Ox"0800"  (* 0x14  HLT *)
].

(** 66 instructions retire, the last one the HLT at 0x14, so PC ends at 0x16 with R2 = F(10) = 0x37
    and R3 = R4 = F(11) = 0x59. *)
Example fibonacci_final_state :
  option_map (fun '(n, s) => (n, observe s)) (run_program 100 fibonacci) =
    Some (66%nat, {| pc := 0x16;
                     gpr := [0; 0; 0x37; 0x59; 0x59; 0; 0x37; 0];
                     halted := true |}).
Proof. vm_compute. reflexivity. Qed.

(** Reset restarts the halted CPU at PC 0 and keeps the registers. *)
Example reset_after_halt :
  option_map observe (
    '(_, s) ← run_program 100 fibonacci;
    after (reset tt) s) =
    Some {| pc := 0; gpr := [0; 0; 0x37; 0x59; 0x59; 0; 0x37; 0]; halted := false |}.
Proof. vm_compute. reflexivity. Qed.
