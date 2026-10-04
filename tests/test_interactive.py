"""Interactive mode, driven through a pseudo-terminal: the screen, the keys and quitting."""

import contextlib
import os
import pty
import re
import select
import subprocess
import termios
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

import pytest

from tara.emulator import Emulator
from tara.keys import Keys

type Program = Callable[[str], Path]
type Start = Callable[..., Session]

INTERACTIVE = "-i"
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
UPPER_HALF_BLOCK = "▀"
CONTROL_SEQUENCE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
# The status line spells the held input lines in Keys order, UP to QUIT, '-' for a released one.
KEY_LETTERS = "UDLRQ"
RELEASED = "-"
TIMEOUT_SECONDS = 10
POLL_SECONDS = 0.02
HOLD_SECONDS = 0.15


class State(StrEnum):
    """The state a status line shows."""

    RUNNING = "running"
    HALTED = "halted"
    ILLEGAL = "illegal"
    LIMIT = "limit"


STATUS_LINE = re.compile(
    rf"({'|'.join(State)})  pc 0x([0-9a-f]{{4}})  steps (\d+)  keys "
    + "".join(f"([{letter}{RELEASED}])" for letter in KEY_LETTERS)
)


@dataclass(frozen=True)
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
        return cls(State(state), int(pc, 16), int(steps), Keys(held))


class Session:
    """An emulator in interactive mode on a pseudo-terminal, as a person would run it."""

    def __init__(self, emulator: Emulator, *arguments: str | Path) -> None:
        self.master, self.terminal = pty.openpty()
        self.settings = termios.tcgetattr(self.terminal)
        self.process = subprocess.Popen(
            [emulator.path, INTERACTIVE, *arguments],
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


@pytest.fixture
def start(emulator: Emulator) -> Iterator[Start]:
    """Starts interactive sessions of the emulator, and cleans up after them."""

    sessions: list[Session] = []

    def start(*arguments: str | Path) -> Session:
        session = Session(emulator, *arguments)
        sessions.append(session)
        return session

    yield start
    for session in sessions:
        session.close()


def in_state(state: State) -> Callable[[Status], bool]:
    return lambda status: status.state == state


def holding(keys: Keys) -> Callable[[Status], bool]:
    return lambda status: status.keys == keys


def test_draws_on_the_alternate_screen_and_restores_the_terminal(
    start: Start, program: Program
) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))
    session.send(ESCAPE)

    assert session.finish() == 0
    output = session.output
    first, last = output.index(State.RUNNING), output.rindex(State.RUNNING)
    assert output.index(ENTER_ALTERNATE_SCREEN) < first
    assert output.index(HIDE_CURSOR) < first
    assert output.rindex(LEAVE_ALTERNATE_SCREEN) > last
    assert output.rindex(SHOW_CURSOR) > last
    assert session.restored()


def test_ctrl_c_quits(start: Start, program: Program) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))
    session.send(CTRL_C)

    assert session.finish() == 0
    assert session.restored()


@pytest.mark.parametrize(
    ("key", "keys"),
    [
        pytest.param("w", Keys.UP, id="w"),
        pytest.param("S", Keys.DOWN, id="S"),
        pytest.param("a", Keys.LEFT, id="a"),
        pytest.param("d", Keys.RIGHT, id="d"),
        pytest.param("q", Keys.QUIT, id="q"),
        pytest.param(f"{CSI}A", Keys.UP, id="up"),
        pytest.param(f"{CSI}B", Keys.DOWN, id="down"),
        pytest.param(f"{CSI}D", Keys.LEFT, id="left"),
        pytest.param(f"{SS3}C", Keys.RIGHT, id="right-application-mode"),
    ],
)
def test_keys_drive_the_input_lines(start: Start, program: Program, key: str, keys: Keys) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))
    session.send(key)

    session.wait_for(holding(keys))
    session.wait_for(holding(Keys(0)))
    session.send(ESCAPE)
    assert session.finish() == 0


def test_key_is_held_after_its_last_press(start: Start, program: Program) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))
    session.send("w")
    pressed = time.monotonic()

    session.wait_for(holding(Keys.UP))
    session.wait_for(holding(Keys(0)))
    assert time.monotonic() - pressed >= HOLD_SECONDS
    session.send(ESCAPE)
    assert session.finish() == 0


def test_halted_program_stays_on_screen_until_quit(start: Start, program: Program) -> None:
    session = start(RATE, "0", program("pixels"))
    halted = session.wait_for(in_state(State.HALTED))
    time.sleep(0.3)

    assert session.process.poll() is None
    assert (halted.pc, halted.steps) == (0x0012, 9)
    assert UPPER_HALF_BLOCK in session.output
    assert AMBER in session.output
    session.send(ESCAPE)
    assert session.finish() == 0


@pytest.mark.parametrize(
    ("name", "options", "state", "exit_status"),
    [
        pytest.param("illegal", [], State.ILLEGAL, 4, id="illegal"),
        pytest.param("spin", ["-n", "50"], State.LIMIT, 3, id="limit"),
    ],
)
def test_exit_status_follows_the_end_of_the_run(
    start: Start, program: Program, name: str, options: list[str], state: State, exit_status: int
) -> None:
    session = start(RATE, "0", *options, program(name))
    session.wait_for(in_state(state))
    session.send(ESCAPE)

    assert session.finish() == exit_status


@pytest.mark.parametrize(
    "options",
    [
        pytest.param(["-t"], id="trace"),
        pytest.param(["--fb"], id="framebuffer"),
        pytest.param(["--keys", "1"], id="keys"),
    ],
)
def test_rejects_batch_options(start: Start, program: Program, options: list[str]) -> None:
    session = start(*options, program("spin"))

    assert session.finish() == 1
    assert ENTER_ALTERNATE_SCREEN not in session.output
    assert session.restored()
