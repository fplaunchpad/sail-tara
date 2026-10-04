"""The emulators' command line: options, image formats, errors and exit statuses."""

import itertools
from pathlib import Path

import pytest

from helpers.programs import Program
from tara.emulator import Emulator, RunOptions, Subcommand
from tara.image import Image
from tara.isa import ILLEGAL, MEMORY_BYTES, REGISTERS, WORD_BYTES
from tara.keys import Keys, KeySchedule
from tara.reference import Reference
from tara.transcript import Status, TraceLine

RUN = Subcommand.RUN
# The registers keys.tara loads from the input port, after 2, 3 and 4 retirements.
INPUT_READS = (1, 3, 4)
# spin.tara jumps to itself.
SPIN = TraceLine(pc=0, word=0xB7FF, registers=(0,) * REGISTERS, assembly="JMP -1")


@pytest.mark.parametrize("keys", ["21", "0x15"])
def test_keys_hold_the_input_lines(emulator: Emulator, program: Program, keys: str) -> None:
    transcript = emulator.invoke(RUN, "--keys", keys, program("keys")).transcript

    assert [transcript.registers[index] for index in INPUT_READS] == [0x15] * 3


def test_key_script_changes_the_input_lines(
    emulator: Emulator, program: Program, tmp_path: Path
) -> None:
    script = tmp_path / "keys.script"
    script.write_text("; STEP KEYS\n3 2 ; from the second read\n\n4 0x4\n")

    run = emulator.invoke(RUN, "--keys", "1", "--key-script", script, program("keys"))

    assert [run.transcript.registers[index] for index in INPUT_READS] == [1, 2, 4]


def test_framebuffer_shows_the_pixels_set(emulator: Emulator, program: Program) -> None:
    transcript = emulator.invoke(RUN, "--framebuffer", program("pixels")).transcript

    assert transcript.pixels == {(0, 0), (63, 63)}


@pytest.mark.parametrize("option", ["-n", "--max-steps"])
def test_step_limit_ends_the_run(emulator: Emulator, program: Program, option: str) -> None:
    transcript = emulator.invoke(RUN, option, "10", program("spin")).transcript

    assert (transcript.status, transcript.steps) == (Status.LIMIT, 10)


@pytest.mark.parametrize("option", ["-t", "--trace"])
def test_trace_prints_a_line_per_step(emulator: Emulator, program: Program, option: str) -> None:
    transcript = emulator.invoke(RUN, option, "-n", "3", program("spin")).transcript

    assert transcript.trace == (SPIN,) * 3


def test_illegal_opcode_ends_the_run(emulator: Emulator, program: Program) -> None:
    transcript = emulator.invoke(RUN, "-t", program("illegal")).transcript
    last = transcript.trace[-1]

    assert (transcript.status, transcript.steps, transcript.pc) == (Status.ILLEGAL, 3, 8)
    assert (last.pc, last.word, last.assembly) == (0x0006, 0xD800, ILLEGAL)


def test_loads_hex_images(
    emulator: Emulator, program: Program, disassembly: tuple[str, ...], tmp_path: Path
) -> None:
    memory = Image(program("keys")).read()
    words = [int.from_bytes(word) for word in itertools.batched(memory, WORD_BYTES, strict=True)]
    image = tmp_path / "keys.hex"
    image.write_text(
        "; 1 to 4 hex digits a word, any case, any spacing\n\n"
        + "".join(f"{word:X}   ; word {index}\n" for index, word in enumerate(words[:-2]))
        + " ".join(f"{word:x}" for word in words[-2:])
        + "\n"
    )
    options = RunOptions(keys=KeySchedule(initial=Keys(9)))

    expected = Reference(memory).run(options, disassembly=disassembly)
    assert emulator.run(image, options).transcript == expected


@pytest.mark.parametrize(
    "options",
    [
        pytest.param(["--bogus"], id="unknown-option"),
        pytest.param(["--keys", "32"], id="keys-too-large"),
        pytest.param(["--keys", "seven"], id="keys-not-a-number"),
        pytest.param(["-n", "-1"], id="negative-step-limit"),
        pytest.param(["-n", "many"], id="step-limit-not-a-number"),
        pytest.param(["--hz", "2000"], id="play-option"),
        pytest.param(["-t", "--trace"], id="trace-aliases"),
        pytest.param(["--trace", "-t"], id="trace-reversed"),
        pytest.param(["-t", "-t"], id="trace-twice"),
        pytest.param(["-n", "10", "--max-steps", "20"], id="step-limit-aliases"),
        pytest.param(["--max-steps", "10", "-n", "20"], id="step-limit-reversed"),
        pytest.param(["-n", "10", "--max-steps", "10"], id="step-limit-same-value"),
        pytest.param(["--keys", "1", "--keys", "2"], id="keys-twice"),
        pytest.param(["--key-script", "first", "--key-script", "second"], id="key-script-twice"),
        pytest.param(["--framebuffer", "--framebuffer"], id="framebuffer-twice"),
    ],
)
def test_run_rejects_bad_options(emulator: Emulator, program: Program, options: list[str]) -> None:
    assert emulator.invoke(RUN, *options, program("keys")).rejected


@pytest.mark.parametrize(
    "options",
    [
        pytest.param([], id="no-terminal"),
        pytest.param(["--hz", "-5"], id="negative-rate"),
        pytest.param(["-n", "10", "--max-steps", "20"], id="step-limit-aliases"),
        pytest.param(["--max-steps", "10", "-n", "20"], id="step-limit-reversed"),
        pytest.param(["--hz", "100", "--hz", "200"], id="rate-twice"),
    ],
)
def test_play_rejects_bad_options(emulator: Emulator, program: Program, options: list[str]) -> None:
    assert emulator.invoke(Subcommand.PLAY, *options, program("spin")).rejected


@pytest.mark.parametrize(
    "arguments",
    [
        pytest.param([], id="no-subcommand"),
        pytest.param(["frobnicate"], id="unknown-subcommand"),
        pytest.param(["--trace"], id="option-without-subcommand"),
        *(
            pytest.param([name], id=name)
            for name in ["r", "ru", "p", "pl", "d", "di", "dis", "disa"]
        ),
        *(pytest.param(["--help", name], id=f"help-{name}") for name in ["r", "pl", "dis"]),
        pytest.param([Subcommand.DISASM, "image.bin"], id="disasm-argument"),
    ],
)
def test_rejects_bad_subcommands(emulator: Emulator, arguments: list[str]) -> None:
    assert emulator.invoke(*arguments).rejected


@pytest.mark.parametrize("subcommand", Subcommand)
def test_help_names_the_subcommand(emulator: Emulator, subcommand: Subcommand) -> None:
    run = emulator.invoke("--help", subcommand)

    assert (run.status, run.stderr) == (0, "")
    assert f"{emulator.name} {subcommand}" in run.stdout


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

    assert emulator.invoke(RUN, "--key-script", path, program("keys")).rejected


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

    assert emulator.invoke(RUN, image).rejected


def test_rejects_a_missing_image(emulator: Emulator, tmp_path: Path) -> None:
    assert emulator.invoke(RUN, tmp_path / "missing.bin").rejected


def test_requires_an_image(emulator: Emulator) -> None:
    assert emulator.invoke(RUN).rejected
