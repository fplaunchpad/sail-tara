"""Every program runs on the emulators exactly as on the reference model: the programs in
tests/programs, TARA Studio's examples, and random programs."""

import random
from collections.abc import Callable
from pathlib import Path

import pytest

from helpers.programs import EXAMPLES, PROGRAMS, STEP_LIMIT, key_schedule, program_id
from helpers.random_programs import random_program
from tara import reference
from tara.asm import assemble_file
from tara.emulator import Emulator
from tara.image import Image
from tara.transcript import Status

RANDOM_PROGRAMS = 50


@pytest.mark.parametrize("source", [*PROGRAMS, *EXAMPLES], ids=program_id)
def test_runs_like_the_reference(
    emulator: Emulator,
    disassembly: tuple[str, ...],
    assemble: Callable[[Path], Path],
    tmp_path: Path,
    source: Path,
) -> None:
    image = assemble(source)
    keys = key_schedule(program_id(source))
    script = tmp_path / "keys.script"
    script.write_text(keys.script())

    run = emulator.run("-t", "-n", str(STEP_LIMIT), "--key-script", script, image)
    expected = reference.run(
        Image(image).read(), keys=keys, max_steps=STEP_LIMIT, disassembly=disassembly
    )

    assert run.transcript == expected
    assert run.status == expected.status.exit_status


@pytest.mark.parametrize("seed", range(RANDOM_PROGRAMS))
def test_random_program_runs_like_the_reference(
    emulator: Emulator, disassembly: tuple[str, ...], tmp_path: Path, seed: int
) -> None:
    source = tmp_path / f"random-{seed}.tara"
    source.write_text(random_program(random.Random(seed)))
    image = Image(tmp_path / f"random-{seed}.bin")
    image.write(assemble_file(source))

    expected = reference.run(image.read(), disassembly=disassembly)
    assert expected.status is Status.HALTED, "random programs must halt"

    run = emulator.run("-t", image.path)

    assert run.transcript == expected, source.read_text()
