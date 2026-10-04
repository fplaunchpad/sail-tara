"""Assertions shared by the tests."""

from tara.emulator import Run


def assert_rejected(run: Run) -> None:
    """A usage or input error: exit status 1, a message on stderr and nothing on stdout."""

    assert (run.status, run.stdout) == (1, "")
    assert run.stderr.strip()
