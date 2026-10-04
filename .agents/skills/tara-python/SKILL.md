---
name: tara-python
description: Python practices and tooling for this repository's hand-written Python (reference-simulator wrappers, differential tests). Read before writing or reviewing any Python here.
---

# Python guidance

Copied from the generic part of the `canard-python` skill
(`~/Projects/canard/.agents/skills/canard-python/SKILL.md`); repository-specific
rules from that skill do not apply here.

## General Python practices

- Keep type aliases beside their owner. Prefer PEP 695 aliases for shared
  spellings; do not introduce wrapper types solely to distinguish `str` or
  `Path` values.
- Use `StrEnum` for string-valued closed choices, `IntEnum` for integer-coded
  interfaces, `IntFlag` for bitmask sets, and ordinary `Enum` for opaque
  choices. Do not invent numeric codes. Preserve explicit wire spellings and
  interpolate `StrEnum` members directly in f-strings. Keep core values
  stable, derive labels and defaults through properties or class methods such
  as `Compiler.default()`, and keep additional metadata in one owner-local
  table. Use the enum-owned default directly in option signatures when
  immutable.
- Validate invariants in constructors as well as at CLI converters when values
  can be constructed internally. Converters return the validated value type.
  Use `Annotated` with `msgspec.Meta` for scalar and container bounds at decode
  boundaries; retain `__post_init__` checks for direct construction because
  field annotations alone do not validate constructor arguments. For counts,
  distinguish integers from booleans and validate finite numeric values
  directly. Use fixed tuple annotations for known record shapes and
  `Meta(min_length=1)` for decoded nonempty collections.
- Resolve each override/document/default field together, using explicit
  `None` checks when zero is invalid but still distinct from a missing value.
- Define fixed spellings once and derive related names from them. Name classes
  and constants without leading underscores.
- Put a named predicate next to its caller when it is complex or single-use.
  Name nontrivial boolean results before combining them with policy decisions.
  Reuse compiled regular expressions, standard-library operations, and existing
  dependency APIs before adding custom helpers. Use a walrus for a short value
  that is immediately tested or rendered, such as
  `if stderr_text := stderr.strip():`; retain a named local when the value has
  broader meaning, is reused, or drives multiple branches.
- Simplify loops with early returns only when they preserve later validation
  and error classification; a mismatch may not justify skipping typed errors.
- Use explicit `if`/`match` branches for diagnostic assembly and multi-step
  decisions. Use a conditional expression for a short, pure value choice, such
  as `rendered = "true" if value else "false"`. Add a
  blank line after each function docstring and after guards and completed
  `if`, `for`, `while`, `try`, `with`, and `match` blocks before independent
  work. Keep related straight-line assignments together; use whitespace at
  logical block boundaries, not as a line-count convention. Keep branch chains
  contiguous, with no blank lines between their arms.
- Name a meaningful intermediate value when it makes nested transformations
  or a multi-part policy easier to read. Keep option and configuration records
  in named locals before passing them to workflow owners. Split long operations
  at semantic stages with explicit inputs and results; avoid arbitrary line
  caps and forwarding-only helpers.
- Construct argument vectors in visible order and pass them without a shell.
  Keep every caller-provided argument as its own argument.
  Keep a named argv tuple when it is reused or retained as provenance; inline a
  one-use tuple only when that keeps invocation clearer.
- Use `*arguments: str` on plain argument-forwarding methods; keep complete
  command vectors where they are composed, recorded, or parsed as a unit. Use
  variadic parameters for individual forwarded items, not merely because an
  input happens to be a tuple. Put fixed metadata parameters first and the
  variadic argv parameter last. Use variadic parameters for homogeneous path or
  target batches when the API represents individual items, after its fixed
  metadata; keep unrelated records and caller-facing Click collections as
  explicit tuples.
- Assign a domain owner to a named local before calling its behavioral method.
- Model caught and persisted failures as typed variants with required context.
  Keep live exception families catchable and serialize owner-local failure
  unions; do not collapse failures into generic `detail` or exception strings.
  When a live exception wraps a frozen failure context, construct and name the
  context before raising it.
  Preserve actual external diagnostics in clearly named fields.

## Command-line interfaces

Adapted from the CLI rules of `canard-python`.

- Write commands with Click. Keep a command to typed conversion, diagnostics,
  and rendering; module functions own the work.
- Use native `click.argument` and `click.option` decorators,
  `click.Path(path_type=Path)` for paths, and `click.Choice` for short closed
  option sets.
- Convert richer values with a `click.ParamType` subclass whose `convert`
  returns the validated domain type and reports problems with `self.fail`. The
  domain type validates the same invariant in its constructor.
- Shared option bundles may use a generic `ParamSpec`/type-parameter decorator
  with stacked Click decorators and `functools.wraps`; forward `*args` and
  `**kwargs` unchanged and preserve the callback signature. Avoid manual
  decorator loops and nested `option(function)` composition.
- Report expected failures as `click.ClickException` subclasses: non-frozen
  `@dataclass(eq=False)` records with typed fields that build their message in
  `__post_init__`. Do not print diagnostics and return exit codes by hand.

## Tooling

- Use `just python lint`, `just python format --check`, and
  `just python typecheck` inside the committed Nix environment. Apply
  formatting with `just python format`; do not use pip or `ruff format`.
- Runtime dependencies are the `[project] dependencies` of `pyproject.toml`
  (currently Click), pinned with `==` to the releases nixpkgs provides. Nix
  builds take them from nixpkgs and refuse to evaluate if a pin drifts, so
  sandboxed builds need neither uv nor network access; uv locks the same
  releases for development with Ruff, Black and Pyright (`just python sync`).
- Pyright runs in strict mode. Untyped third-party modules get hand-written
  stubs under `typings/` instead of casts or `type: ignore` comments.
