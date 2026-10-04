# Lem backend uses the unescaped register name for state access

## Reproducer

With Sail 0.20.3, compile this model using the Lem backend:

```sail
default Order dec
$include <prelude.sail>

register MEM : bits(8)

function read_mem() -> bits(8) = { MEM }

function write_mem(value : bits(8)) -> unit = { MEM = value }
```

```sh
mkdir -p generated
sail --lem --lem-output-dir generated --isa-output-dir generated -o repro model.sail
lem -wl err -wl_auto_import ign -lib "$SAIL_DIR/src/gen_lib" \
  generated/repro_types.lem generated/repro.lem
```

Sail emits a record field named `MEM'`, but the register reference uses the unescaped name:

```lem
type regstate = <| MEM' : list bitU; |>
read_from = (fun s -> s.MEM)
write_to = (fun v s -> (<| s with MEM = v |>))
```

Lem rejects the generated file with a syntax error at the `s.MEM` access. Names that need escaping in the generated record should use the same spelling in register reads and writes.

## Proposed fix

Pass the same identifier formatter used by the Lem record printer into `register_refs_lem`, and use it for non-memory register field accesses. The change is small and keeps the existing default for other callers. A focused patch and pinned before/after check are in the attached reproduction.
