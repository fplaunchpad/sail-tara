"""The emulators' command line: options, image formats, errors and exit status."""

from collections.abc import Callable
from pathlib import Path

import pytest

from tara import reference
from tara.emulator import Emulator, Run
from tara.image import Image
from tara.isa import MEMORY_BYTES
from tara.keys import KeySchedule
from tara.transcript import Status

type Program = Callable[[str], Path]

# The registers keys.tara loads from the input port, after 2, 3 and 4 retirements.
INPUT_READS = (1, 3, 4)
SPIN_STEP = "0000 b7ff " + "0000 " * 8 + "JMP -1"


def assert_rejected(run: Run) -> None:
    """A usage or input error: exit status 1, a message on stderr and nothing on stdout."""

    assert (run.status, run.stdout) == (1, "")
    assert run.stderr.strip()


@pytest.mark.parametrize("keys", ["21", "0x15"])
def test_keys_hold_the_input_lines(emulator: Emulator, program: Program, keys: str) -> None:
    transcript = emulator.run("--keys", keys, program("keys")).transcript

    assert [transcript.registers[index] for index in INPUT_READS] == [0x15, 0x15, 0x15]


def test_key_script_changes_the_input_lines(
    emulator: Emulator, program: Program, tmp_path: Path
) -> None:
    script = tmp_path / "keys.script"
    script.write_text("; STEP KEYS\n3 2 ; from the second read\n\n4 0x4\n")

    transcript = emulator.run("--keys", "1", "--key-script", script, program("keys")).transcript

    assert [transcript.registers[index] for index in INPUT_READS] == [1, 2, 4]


def test_framebuffer_shows_the_pixels_set(emulator: Emulator, program: Program) -> None:
    transcript = emulator.run("--fb", program("pixels")).transcript

    assert transcript.pixels == {(0, 0), (63, 63)}


@pytest.mark.parametrize("option", ["-n", "--max-steps"])
def test_step_limit_ends_the_run(emulator: Emulator, program: Program, option: str) -> None:
    run = emulator.run(option, "10", program("spin"))

    assert (run.status, run.transcript.status, run.transcript.steps) == (3, Status.LIMIT, 10)


@pytest.mark.parametrize("option", ["-t", "--trace"])
def test_trace_prints_a_line_per_step(emulator: Emulator, program: Program, option: str) -> None:
    transcript = emulator.run(option, "-n", "3", program("spin")).transcript

    assert [step.render() for step in transcript.trace] == [SPIN_STEP] * 3


def test_illegal_opcode_ends_the_run(emulator: Emulator, program: Program) -> None:
    run = emulator.run("-t", program("illegal"))
    transcript = run.transcript
    last = transcript.trace[-1]

    assert (run.status, transcript.status, transcript.steps) == (4, Status.ILLEGAL, 3)
    assert (last.pc, last.word, last.assembly, transcript.pc) == (0x0006, 0xD800, "illegal", 8)


def test_loads_hex_images(emulator: Emulator, program: Program, tmp_path: Path) -> None:
    memory = Image(program("keys")).read()
    words = [int.from_bytes(memory[index : index + 2]) for index in range(0, len(memory), 2)]
    image = tmp_path / "keys.hex"
    image.write_text(
        "; 1 to 4 hex digits a word, any case, any spacing\n\n"
        + "".join(f"{word:X}   ; word {index}\n" for index, word in enumerate(words[:-2]))
        + " ".join(f"{word:x}" for word in words[-2:])
        + "\n"
    )

    transcript = emulator.run("--keys", "9", image).transcript

    assert transcript == reference.run(memory, keys=KeySchedule(9))


@pytest.mark.parametrize(
    "options",
    [
        pytest.param(["--bogus"], id="unknown-option"),
        pytest.param(["--keys", "32"], id="keys-too-large"),
        pytest.param(["--keys", "seven"], id="keys-not-a-number"),
        pytest.param(["-n", "-1"], id="negative-step-limit"),
        pytest.param(["-n", "many"], id="step-limit-not-a-number"),
        pytest.param(["--hz", "-5"], id="negative-rate"),
        pytest.param(["--interactive"], id="interactive-without-a-terminal"),
    ],
)
def test_rejects_bad_options(emulator: Emulator, program: Program, options: list[str]) -> None:
    assert_rejected(emulator.run(*options, program("keys")))


@pytest.mark.parametrize(
    "script",
    [
        pytest.param("4 1\n3 2\n", id="steps-decreasing"),
        pytest.param("3 1\n3 2\n", id="steps-repeated"),
        pytest.param("3\n", id="keys-missing"),
        pytest.param("3 32\n", id="keys-too-large"),
        pytest.param("-1 2\n", id="step-negative"),
        pytest.param("x 2\n", id="step-not-a-number"),
        pytest.param("3 2 1\n", id="extra-field"),
    ],
)
def test_rejects_bad_key_scripts(
    emulator: Emulator, program: Program, tmp_path: Path, script: str
) -> None:
    path = tmp_path / "keys.script"
    path.write_text(script)

    assert_rejected(emulator.run("--key-script", path, program("keys")))


@pytest.mark.parametrize(
    ("name", "contents"),
    [
        pytest.param("big.bin", bytes(MEMORY_BYTES + 1), id="larger-than-memory"),
        pytest.param("big.hex", b"0000\n" * (MEMORY_BYTES // 2 + 1), id="hex-larger-than-memory"),
        pytest.param("digit.hex", b"12g4\n", id="hex-not-a-digit"),
        pytest.param("long.hex", b"12345\n", id="hex-word-too-long"),
        pytest.param("image.txt", b"0800\n", id="unknown-suffix"),
    ],
)
def test_rejects_bad_images(emulator: Emulator, tmp_path: Path, name: str, contents: bytes) -> None:
    image = tmp_path / name
    image.write_bytes(contents)

    assert_rejected(emulator.run(image))


def test_rejects_a_missing_image(emulator: Emulator, tmp_path: Path) -> None:
    assert_rejected(emulator.run(tmp_path / "missing.bin"))


def test_requires_an_image(emulator: Emulator) -> None:
    assert_rejected(emulator.run())


def test_disassembly_takes_no_image(emulator: Emulator, program: Program) -> None:
    assert_rejected(emulator.run("--disasm-all", program("keys")))
