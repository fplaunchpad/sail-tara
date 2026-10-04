"""An emulator in interactive mode on a pseudo-terminal, and what its screen shows."""

import contextlib
import os
import pty
import re
import select
import subprocess
import termios
import time
from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum, auto
from pathlib import Path

from tara.emulator import Emulator, Subcommand
from tara.keys import Keys

RATE = "--hz"
ESCAPE = "\x1b"
CTRL_C = "\x03"
CSI = "\x1b["  # arrow keys in normal cursor mode
SS3 = "\x1bO"  # arrow keys in application cursor mode
ENTER_ALTERNATE_SCREEN = "\x1b[?1049h"
LEAVE_ALTERNATE_SCREEN = "\x1b[?1049l"
HIDE_CURSOR = "\x1b[?25l"
SHOW_CURSOR = "\x1b[?25h"
AMBER = "38;2;255;176;0"
UPPER_HALF_BLOCK = "\u2580"
CONTROL_SEQUENCE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
# The status line spells the held input lines in Keys order, UP to QUIT, '-' for a released one.
KEY_LETTERS = "UDLRQ"
RELEASED = "-"
TIMEOUT_SECONDS = 10
POLL_SECONDS = 0.02
HOLD_SECONDS = 0.15


class State(StrEnum):
    """The state a status line shows."""

    RUNNING = auto()
    HALTED = auto()
    ILLEGAL = auto()
    LIMIT = auto()


STATUS_LINE = re.compile(
    rf"({'|'.join(State)})  pc 0x([0-9a-f]{{4}})  steps (\d+)  keys "
    + "".join(f"([{letter}{RELEASED}])" for letter in KEY_LETTERS)
)


@dataclass(frozen=True, kw_only=True)
class Status:
    """A status line: the run's state, PC, retirements and held input lines."""

    state: State
    pc: int
    steps: int
    keys: Keys

    @classmethod
    def parse(cls, match: re.Match[str]) -> Status:
        state, pc, steps, *lines = match.groups()
        held = sum(1 << index for index, line in enumerate(lines) if line != RELEASED)
        return cls(state=State(state), pc=int(pc, 16), steps=int(steps), keys=Keys(held))


class Session:
    """An emulator in interactive mode on a pseudo-terminal, as a person would run it."""

    def __init__(self, emulator: Emulator, *arguments: str | Path) -> None:
        self.master, self.terminal = pty.openpty()
        self.settings = termios.tcgetattr(self.terminal)
        self.process = subprocess.Popen(
            [emulator.path, Subcommand.PLAY, *arguments],
            stdin=self.terminal,
            stdout=self.terminal,
            stderr=self.terminal,
            start_new_session=True,
        )
        self.drawn = b""

    @property
    def output(self) -> str:
        """Everything drawn so far."""

        return self.drawn.decode(errors="replace")

    def read(self, timeout: float) -> None:
        """Take whatever the emulator has drawn, waiting up to `timeout` seconds for it."""

        ready, _write, _error = select.select([self.master], [], [], timeout)
        if ready:
            # Reading fails with EIO once the emulator has exited and closed its side.
            with contextlib.suppress(OSError):
                self.drawn += os.read(self.master, 1 << 16)

    def send(self, keys: str) -> None:
        os.write(self.master, keys.encode())

    def statuses(self) -> list[Status]:
        text = CONTROL_SEQUENCE.sub("", self.output)
        return [Status.parse(match) for match in STATUS_LINE.finditer(text)]

    def wait_for(self, wanted: Callable[[Status], bool]) -> Status:
        """The first status line drawn from now on that `wanted` accepts."""

        seen = len(self.statuses())
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            exited = self.process.poll() is not None
            self.read(POLL_SECONDS)
            if found := next(filter(wanted, self.statuses()[seen:]), None):
                return found

            if exited:
                raise AssertionError(f"exited with status {self.process.returncode} instead")

        raise AssertionError(f"no such status line; the last was {self.statuses()[-1:]}")

    def finish(self) -> int:
        """Keep reading until the emulator exits; its exit status."""

        deadline = time.monotonic() + TIMEOUT_SECONDS
        while self.process.poll() is None:
            if time.monotonic() > deadline:
                raise AssertionError("the emulator did not exit")

            self.read(POLL_SECONDS)

        self.read(0)
        return self.process.returncode

    def restored(self) -> bool:
        """Whether the terminal settings are back to what they were before the emulator ran."""

        return termios.tcgetattr(self.terminal) == self.settings

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()

        os.close(self.master)
        os.close(self.terminal)


# The `start` fixture: starts a session with the given arguments after `play`.
type Start = Callable[..., Session]


def in_state(state: State) -> Callable[[Status], bool]:
    return lambda status: status.state == state


def holding(keys: Keys) -> Callable[[Status], bool]:
    return lambda status: status.keys == keys
