# Shared execution policy for the root justfile and its modules.
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set positional-arguments
set lazy
