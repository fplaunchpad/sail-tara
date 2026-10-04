# Locked Python development tools (Ruff, Black, Pyright) via uv.
import "settings.just"

set working-directory := ".."

# Lint, check the formatting of and type-check the Python sources.
[default]
[group('quality')]
lint: ruff format-check typecheck

# Lint the Python sources with Ruff; ARGS go to it (e.g. --fix).
[group('quality')]
ruff *args:
    uv run --frozen --no-python-downloads ruff check tools typings tests "$@"

# Check the formatting of the Python sources.
[private]
format-check:
    uv run --frozen --no-python-downloads black --check tools typings tests

# Format the Python sources with Black.
[group('quality')]
format:
    uv run --frozen --no-python-downloads black tools typings tests

# Type-check the Python sources strictly, against the test interpreter's packages.
[group('quality')]
typecheck:
    uv run --frozen --no-python-downloads pyright --pythonpath "$TARA_PYTHON"

# Install the locked development tools.
[group('dependencies')]
sync:
    uv sync --frozen --no-python-downloads

# Check that the lock file matches pyproject.toml.
[group('dependencies')]
lock-check:
    uv lock --check --no-python-downloads
