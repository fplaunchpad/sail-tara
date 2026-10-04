"""Interactive mode, driven through a pseudo-terminal: the screen, the keys and quitting."""

import time

import pytest

from helpers.programs import ProgramImage
from helpers.terminal import (
    AMBER,
    CSI,
    CTRL_C,
    ENTER_ALTERNATE_SCREEN,
    ESCAPE,
    HIDE_CURSOR,
    HOLD_SECONDS,
    LEAVE_ALTERNATE_SCREEN,
    RATE,
    SHOW_CURSOR,
    SS3,
    UPPER_HALF_BLOCK,
    Start,
    State,
    holding,
    in_state,
)
from tara.keys import Keys


def test_draws_on_the_alternate_screen_and_restores_the_terminal(
    start: Start, program: ProgramImage
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


def test_ctrl_c_quits(start: Start, program: ProgramImage) -> None:
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
def test_keys_drive_the_input_lines(
    start: Start, program: ProgramImage, key: str, keys: Keys
) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))
    session.send(key)

    session.wait_for(holding(keys))
    session.wait_for(holding(Keys(0)))
    session.send(ESCAPE)
    assert session.finish() == 0


def test_key_is_held_after_its_last_press(start: Start, program: ProgramImage) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))
    session.send("w")
    pressed = time.monotonic()

    session.wait_for(holding(Keys.UP))
    session.wait_for(holding(Keys(0)))
    assert time.monotonic() - pressed >= HOLD_SECONDS
    session.send(ESCAPE)
    assert session.finish() == 0


def test_halted_program_stays_on_screen_until_quit(start: Start, program: ProgramImage) -> None:
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
    start: Start,
    program: ProgramImage,
    name: str,
    options: list[str],
    state: State,
    exit_status: int,
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
def test_rejects_batch_options(start: Start, program: ProgramImage, options: list[str]) -> None:
    session = start(*options, program("spin"))

    assert session.finish() == 1
    assert ENTER_ALTERNATE_SCREEN not in session.output
    assert session.restored()
