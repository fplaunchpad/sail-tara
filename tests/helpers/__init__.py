"""Support for the emulator test suite: everything the tests use that is not itself a test."""

import pytest

# Show the operands of failed assertions in the helpers, as pytest does in the tests. This runs
# before any helper module is imported, which the registration requires.
pytest.register_assert_rewrite("helpers.assertions")
