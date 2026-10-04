(** Reject axioms in the published properties. The build checks this file's output. *)
From Tara Require Import Progress Invariant Halted Illegal Frame Codec.

Print Assumptions step_progress.
Print Assumptions step_one_outcome.
Print Assumptions run_instruction_progress.
Print Assumptions reset_progress.
Print Assumptions fetch_progress.
Print Assumptions step_preserves_wf.
Print Assumptions run_instruction_preserves_wf.
Print Assumptions step_masks_pc.
Print Assumptions reset_establishes_wf.
Print Assumptions power_on_wf.
Print Assumptions halted_step.
Print Assumptions halted_run_instruction.
Print Assumptions decode_none_iff.
Print Assumptions step_illegal.
Print Assumptions illegal_only.
Print Assumptions only_stores_change_memory.
Print Assumptions only_hlt_changes_halted.
Print Assumptions hlt_halts.
Print Assumptions non_branches_advance_pc.
Print Assumptions step_runs_instruction.
Print Assumptions instruction_roundtrip.
