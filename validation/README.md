# v0.5 validation status

This directory separates source review from native Sail validation.

`source_review.json` is produced by `python3 validation/review_source.py`. It
records checks of 27 co-located constructor/mapping/execution groups, all 55,296
tagged 11-bit payloads, the unchanged partial opcode assignment, all execution
body edits after alpha-renaming, include paths, and selected source-ordering
invariants. It also contains finite Python equation checks and negative controls.

`baseline_layouts.json` is the retained field-layout fixture extracted from
v0.2. `baseline_execution.json` contains execution-clause text from v0.4.
Neither fixture is independent hardware evidence. The audit does not implement
Sail syntax, typing, effects, evaluation, or compiler transformations. A passing
source review is not a passing Sail test suite.

`make_dry_run.txt` shows the commands for the build targets, not their execution.
`sail_check_attempt.txt` and `sail_check_exit_code.txt` record the actual attempt
at `make check`, which stopped because the Sail executable is absent. Native
parse/type checks, generated C tests, and Rocq generation remain unperformed.

`v0_4_to_v0_5.patch` is the change to production and native-test sources. There
is no re-labelling of old native results: none are claimed.
