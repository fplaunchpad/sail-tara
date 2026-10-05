"""Verilator's input responsiveness and terminal cleanup."""

import contextlib
import os
import pty
import select
import signal
import subprocess
import termios
import time

import pytest

from helpers.programs import Program
from helpers.terminal import (
    CSI,
    ESCAPE,
    LEAVE_ALTERNATE_SCREEN,
    POLL_SECONDS,
    RATE,
    SHOW_CURSOR,
    TIMEOUT_SECONDS,
    Start,
    State,
    holding,
    in_state,
)
from tara.emulator import Emulator, Subcommand
from tara.keys import Keys

VERILATOR = "tara-verilator"
CLEAR_SCREEN = f"{CSI}2J"
RUNNING = State.RUNNING.encode()
READ_BYTES = 1 << 16
QUEUE_CHUNK_BYTES = 4096
MAX_QUEUE_WRITES = 64


@pytest.fixture(autouse=True)
def require_verilator(emulator: Emulator) -> None:
    if emulator.name != VERILATOR:
        pytest.skip("Verilator frontend regression")


@pytest.mark.parametrize(
    "instructions_per_second",
    [
        pytest.param("0", id="unlimited"),
        pytest.param(str((1 << 64) - 1), id="saturated"),
    ],
)
def test_full_cpu_frames_still_handle_input(
    start: Start, program: Program, instructions_per_second: str
) -> None:
    session = start(RATE, instructions_per_second, program("spin"))
    session.wait_for(in_state(State.RUNNING))
    session.send(f"{CSI}A")

    session.wait_for(holding(Keys.UP))
    session.wait_for(holding(Keys(0)))
    session.send(ESCAPE)

    assert session.finish() == 0
    assert session.restored()


@pytest.mark.parametrize("signal_number", [signal.SIGTERM, signal.SIGINT])
def test_os_signal_restores_the_terminal(
    start: Start, program: Program, signal_number: signal.Signals
) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))

    session.process.send_signal(signal_number)
    status = session.finish()

    assert status == -signal_number
    assert session.restored()
    assert LEAVE_ALTERNATE_SCREEN in session.output
    assert SHOW_CURSOR in session.output


def test_signal_cleanup_does_not_wait_for_output(start: Start, program: Program) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))
    was_blocking = os.get_blocking(session.terminal)
    os.set_blocking(session.terminal, False)
    try:
        for _ in range(MAX_QUEUE_WRITES):
            try:
                os.write(session.terminal, b"." * QUEUE_CHUNK_BYTES)
            except BlockingIOError:
                break

        else:
            pytest.fail("the pseudo-terminal output queue did not fill")

        session.process.send_signal(signal.SIGTERM)
        status = session.process.wait(timeout=TIMEOUT_SECONDS)

        assert status == -signal.SIGTERM
        assert session.restored()
        assert not os.get_blocking(session.terminal)
    finally:
        os.set_blocking(session.terminal, was_blocking)


def test_resize_repaints_the_screen(start: Start, program: Program) -> None:
    session = start(RATE, "1000", program("spin"))
    session.wait_for(in_state(State.RUNNING))
    repaints = session.output.count(CLEAR_SCREEN)

    termios.tcsetwinsize(session.terminal, (40, 80))
    # The child has no controlling terminal; notify it explicitly as a terminal would.
    session.process.send_signal(signal.SIGWINCH)
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while session.output.count(CLEAR_SCREEN) == repaints and time.monotonic() < deadline:
        session.read(POLL_SECONDS)

    assert session.output.count(CLEAR_SCREEN) > repaints
    session.send(ESCAPE)
    assert session.finish() == 0
    assert session.restored()


def test_output_failure_restores_the_input_terminal(emulator: Emulator, program: Program) -> None:
    with contextlib.ExitStack() as resources:
        input_master, input_terminal = pty.openpty()
        output_master, output_terminal = pty.openpty()
        for descriptor in (input_master, input_terminal, output_terminal):
            resources.callback(os.close, descriptor)

        output = resources.enter_context(os.fdopen(output_master, "rb", buffering=0))
        original = termios.tcgetattr(input_terminal)
        process = resources.enter_context(
            subprocess.Popen(
                [emulator.path, Subcommand.PLAY, RATE, "1000", program("spin")],
                stdin=input_terminal,
                stdout=output_terminal,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
        )
        resources.callback(process.kill)
        drawn = b""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while RUNNING not in drawn and time.monotonic() < deadline:
            ready, _, _ = select.select([output], [], [], POLL_SECONDS)
            if ready:
                drawn += os.read(output.fileno(), READ_BYTES)

        assert RUNNING in drawn
        output.close()
        _, error = process.communicate(timeout=TIMEOUT_SECONDS)

        assert process.returncode == 1
        assert error
        assert termios.tcgetattr(input_terminal) == original
