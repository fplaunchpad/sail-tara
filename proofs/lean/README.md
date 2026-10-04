# Lean proofs

These proofs import the Sail-generated Lean model from `model/tara.sail`. Instruction encodings, decoding, execution, stepping, reset, and initialization remain defined by Sail; the Lean project adds state views, lemmas, and properties. Proof modules are in `Tara/` and the generated project is assembled in `build/lean`.

Build and check the published theorem assumptions inside `nix develop --no-update-lock-file`:

```sh
just lean
just lean lint
```

The build generates the model, copies the pinned local `lean-sail` library and these proof files, then builds the project with Lake. `#standard_axioms` in `Tara/Properties.lean` rejects any listed property theorem that depends on a nonstandard axiom.

The main results are:

- `Decode.lean`: `decode`, what `encdec_backwards` returns as an option; `decode_eq_none_iff`, and the run lemmas that let `step`'s proofs use it.
- `Codec.lean`: `encode_opcode`, `decode_encode` and `encode_injective` for `encdec_forwards`.
- `Execute.lean`: `execute_spec` shows that each of the 27 generated instruction cases succeeds and changes only what `ExecuteFrame` permits; `execute_frame` gives that frame for any successful execution.
- `Step.lean`: `StepCase` describes the halted, illegal-opcode and decoded-instruction outcomes, including the 11-bit PC mask and frame properties; `step_spec` shows that every step has one of them.
- `Properties.lean`: progress, PC-bound preservation, absorbing halt, illegal-step, sequential-PC, and memory/halt frame theorems.
- `Machine.lean`: machine values are views of the generated Sail register map. `readByte` and `readWord` evaluate generated Sail functions; the run lemmas show they succeed on machine views.

`reset_wf` proves the generated reset behavior. `sail_model_init_wf` and `power_on_safe` separately prove the generated initializer's zero-choice behavior and safe execution of any input-step list.
