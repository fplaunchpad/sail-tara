---
name: tara-just
description: Write and refactor this repository's Just recipes using the pinned Just version and recipe organization. Read before editing the justfile or just/*.just.
---

# Just guidance

Copied from the generic parts of the `canard-just` skill
(`~/Projects/canard/.agents/skills/canard-just/SKILL.md`); repository-specific
rules from that skill do not apply here. Confirm syntax against the pinned Just
version in the flake (currently Just 1.58.0).

## General Just practices

Prefer Just's native modules, parameters, prerequisites, help, listing, and
working-directory facilities to custom dispatch. Treat recipe parameters as
individual arguments, preserve their boundaries with positional arguments and
`"$@"`, and avoid interpolating user input into shell text. Ordinary recipe
lines run independently; use a script only when shared shell state is needed.

## Recipe organization

Use `mod` for namespaces such as `python`. Modules have independent settings
and default working directories. `import` shared settings explicitly in each
module, and set the intended directory when a module's recipes expect
repository-root paths. See the [Just modules
manual](https://just.systems/man/en/modules.html).

Break multi-step work into single-command recipes and compose them with
prerequisites (for example generate, then compile, then run), rather than
chaining shell commands inside one recipe.

## Wrappers and arguments

Keep ordinary wrappers thin: delegate behavior and option parsing to the tool
being wrapped. Use `*args` for optional forwarding and `+args` when at least
one argument is required. With `set positional-arguments`, forward with `"$@"`
to preserve each argument's boundary; do not interpolate user arguments into
shell text. See the [positional arguments
manual](https://just.systems/man/en/positional-arguments.html).

## Just features and execution

Use recipe option attributes such as `[arg("config", long="config")]` when
Just owns an option. Forward tool-owned options to the tool without creating a
second Just parser for them. Prefer native modules, groups, prerequisites,
listing, and help over custom dispatch. See the [recipe parameters
manual](https://just.systems/man/en/recipe-parameters.html).

Keep ordinary wrappers as single commands. Just runs ordinary recipe lines in
separate shells; use a script recipe only when shared shell state is needed.
Use `[no-cd]` when a recipe must run from the caller's directory. Modules have
their own default working directories, so check this when moving a recipe. See
the [working directory manual](https://just.systems/man/en/working-directory.html).

## Discovery and review

Use `just --list`, `just --show RECIPE`, `just --usage RECIPE`, and
`just --dry-run RECIPE ...` to inspect recipe names, definitions, arguments,
and expanded commands. Check formatting with `just --fmt --check`. Verify
features against the pinned Just version rather than assuming newer syntax.
