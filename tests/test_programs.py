"""Every program runs on the emulators exactly as on the reference model: the test programs,
TARA Studio's examples, and random programs that always halt."""

from collections.abc import Callable
from pathlib import Path

import pytest
from hypothesis import given

from helpers.programs import KEY_PERIOD, PROGRAMS, STEP_LIMIT, STUDIO_EXAMPLES, program_id
from tara.asm import assemble_file
from tara.assembly import Program
from tara.emulator import Emulator, RunOptions
from tara.image import Image
from tara.keys import KeySchedule
from tara.reference import Reference
from tara.strategies import programs
from tara.transcript import Status


@pytest.mark.parametrize("source", [*PROGRAMS, *STUDIO_EXAMPLES], ids=program_id)
def test_runs_like_the_reference(
    emulator: Emulator,
    disassembly: tuple[str, ...],
    assemble: Callable[[Path], Path],
    source: Path,
) -> None:
    image = assemble(source)
    keys = KeySchedule.random(seed=program_id(source), period=KEY_PERIOD, until=STEP_LIMIT)
    options = RunOptions(trace=True, max_steps=STEP_LIMIT, keys=keys, framebuffer=True)

    expected = Reference(Image(image).read()).run(options, disassembly=disassembly)
    assert emulator.run(image, options).transcript == expected


@given(program=programs)
def test_random_program_runs_like_the_reference(
    emulator: Emulator, disassembly: tuple[str, ...], scratch: Path, program: Program
) -> None:
    source = scratch / f"{emulator.name}.tara"
    source.write_text(str(program))
    image = Image(scratch / f"{emulator.name}.bin")
    image.write(assemble_file(source))
    options = RunOptions(trace=True, framebuffer=True)

    expected = Reference(image.read()).run(options, disassembly=disassembly)
    assert expected.status is Status.HALTED, "random programs always halt"
    assert emulator.run(image.path, options).transcript == expected
