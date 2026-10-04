# Lean proofs

These proofs import the Sail-generated Lean model from `model/tara.sail`. Instruction encodings, decoding, execution, stepping, reset, and initialization remain defined by Sail; the Lean project adds state views, lemmas, and properties. Proof modules are in `Tara/` and the generated project is assembled in `build/lean`.

Build and check the published theorem assumptions inside `nix develop --no-update-lock-file`:

```sh
just lean
just lean lint
```

The build generates the model, copies the pinned local `lean-sail` library and these proof files, then builds the project with Lake. `#standard_axioms` in `Tara/Properties.lean` rejects any listed property theorem that depends on a nonstandard axiom.

The main results are:

- `Codec.lean`: `encode_opcode`, `decode_encode`, `encode_injective`, and `decode_eq_none_iff`.
- `Execute.lean`: `execute_spec` describes all 27 generated instruction cases and the permitted register changes; `execute_frame` derives frame conditions for any successful execution.
- `Step.lean`: `step_spec` covers halted, illegal-opcode, and decoded-instruction cases, including the 11-bit PC mask and frame properties.
- `Properties.lean`: progress, PC-bound preservation, absorbing halt, illegal-step, sequential-PC, and memory/halt frame theorems.
- `Machine.lean`: machine values are views of the generated Sail register map. `readByte` and `readWord` evaluate generated Sail functions; the run lemmas show they succeed on machine views.

`reset_wf` proves the generated reset behavior. `sail_model_init_wf` and `power_on_safe` separately prove the generated initializer's zero-choice behavior and safe execution of any input-step list.
