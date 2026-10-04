# Rocq proofs

These proofs compile against Sail-generated Rocq definitions from `model/tara.sail`. They do not restate the instruction encodings or execution functions. The generated model is in `build/rocq`; the handwritten theorem files are in `Tara/`.

Build and audit the proofs inside `nix develop --no-update-lock-file`:

```sh
just rocq
just rocq lint
```

The default build compiles the generated types and definitions, then the proofs, and runs the assumption audit. Build products are written to `build/rocq`.

The results cover:

- `Decode.v`: `decode`, what `encdec_backwards_matches` and `encdec_backwards` return as one option, which the theorems about `step` use.
- `Codec.v`: `instruction_roundtrip`, that decoding the word `encdec` encodes an instruction as returns the instruction. The proof checks all 30,355 constructor/operand combinations.
- `Progress.v`: `step`, `run_instruction`, and `reset` complete; `step_one_outcome` establishes a single Sail state-lifting outcome for every choice source.
- `Invariant.v`: the PC bound `PC < 0x800` is preserved by steps from well-formed states; a running step masks PC even from an otherwise ill-formed state. Reset establishes the bound.
- `Halted.v`: a halted CPU's `step` and `run_instruction` return `Stopped` and leave the machine unchanged.
- `Illegal.v`: exactly opcodes 27–31 fail to decode; an illegal step advances the masked PC and preserves registers other than KEYS and PC.
- `Frame.v`: only stores change memory, only HLT changes the halt latch, and non-branching instructions advance PC sequentially.

`Machine.v` supplies a small evaluator for generated actions that read and write registers. It returns no result for other monad effects; `exec_sound` relates completed evaluations to Sail's `liftState`. The progress proofs establish completion for the model actions covered here.

Rocq's `power_on` helper applies generated `reset` to generated `init_regstate`. It does not run `sail_model_init`; `power_on_wf` proves only the resulting PC and halt properties of that helper.
