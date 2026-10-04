# Locked Python development tools (Ruff, Black, Pyright) via uv.
import "settings.just"
set working-directory := ".."

default:
    @just --list python

[group('dependencies')]
sync:
    uv sync --frozen --no-python-downloads

[group('dependencies')]
lock-check:
    uv lock --check --no-python-downloads

# Lint Python sources and imports with Ruff.
[group('quality')]
lint *args:
    uv run --frozen --no-python-downloads ruff check tools typings tests "$@"

# Format Python with Black; pass --check to inspect without changes.
[group('quality')]
format *args:
    uv run --frozen --no-python-downloads black tools typings tests "$@"

# Check Python types with the strict project configuration, against the test interpreter's packages.
[group('quality')]
typecheck *args:
    uv run --frozen --no-python-downloads pyright --pythonpath "$TARA_PYTHON" "$@"
