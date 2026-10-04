"""Every program runs on the emulators exactly as on the reference model: the programs in
tests/programs, TARA Studio's examples, and random programs."""

import random
from collections.abc import Callable
from pathlib import Path

import pytest
from src.paths import PROGS_DIR

from tara import reference
from tara.asm import assemble_file
from tara.emulator import Emulator
from tara.image import Image
from tara.keys import ALL_KEYS, KeySchedule

PROGRAMS = sorted((Path(__file__).parent / "programs").glob("*.tara"))
EXAMPLES = sorted(Path(PROGS_DIR).rglob("*.tara"))
# Some examples never halt, and the OCaml emulator runs 15 to 30 thousand steps a second.
STEP_LIMIT = 30_000
# Retirements between changes of the input lines, which the games read.
KEY_PERIOD = 97
RANDOM_PROGRAMS = 50
RANDOM_LENGTH = 200


def program_id(source: Path) -> str:
    return f"{source.parent.name}/{source.stem}"


def key_schedule(seed: str) -> KeySchedule:
    """Input lines that change every KEY_PERIOD retirements, seeded by the program's name."""

    rng = random.Random(seed)
    changes = tuple((step, rng.randint(0, ALL_KEYS)) for step in range(0, STEP_LIMIT, KEY_PERIOD))
    return KeySchedule(changes=changes)


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

    run = emulator.run("-t", image.path)

    expected = reference.run(image.read(), disassembly=disassembly)

    assert run.transcript == expected, source.read_text()


# Random programs keep R7 as a pointer into a data page (0x400, 0x500 or 0x600), well clear of
# the code; only PUSH and POP move it. Every other instruction may use any register.
DATA_PAGES = (4, 5, 6)
DATA_REGISTERS = [f"R{index}" for index in range(7)]
REGISTERS = [*DATA_REGISTERS, "R7"]
SKIP_LIMIT = 8
PROLOGUE = "LIL R7, 0\nLIH R7, {page}\n"
EPILOGUE = "HLT\n"
# Instruction templates: rd is a data register, rs1 and rs2 any register, byte and signed_byte
# immediates, offset a 5-bit offset from R7, and skip a forward branch distance.
TEMPLATES = (
    *(
        f"{alu} {{rd}}, {{rs1}}, {{rs2}}"
        for alu in ["ADD", "SUB", "MUL", "AND", "OR", "XOR", "SLT"]
    ),
    "MOV {rd}, {rs1}",
    "NOT {rd}, {rs1}",
    "LIL {rd}, {byte}",
    "LIH {rd}, {byte}",
    "SHL {rd}, {byte}",
    "SHR {rd}, {byte}",
    "ADDI {rd}, {signed_byte}",
    "LDW {rd}, {offset}(R7)",
    "LDB {rd}, {offset}(R7)",
    "STW {rs1}, {offset}(R7)",
    "STB {rs1}, {offset}(R7)",
    "PUSH {rs1}",
    "POP {rd}",
    "BZ {rs1}, {skip}",
    "BN {rs1}, {skip}",
    "JMP {skip}",
    "NOP",
)


def random_program(rng: random.Random) -> str:
    """Straight-line code with random operands, memory accesses through R7 and forward
    branches, ending in HLT."""

    body = (random_instruction(rng, RANDOM_LENGTH - index) for index in range(RANDOM_LENGTH))
    return PROLOGUE.format(page=rng.choice(DATA_PAGES)) + "".join(body) + EPILOGUE


def random_instruction(rng: random.Random, remaining: int) -> str:
    """One instruction, at most `remaining` instructions before the final HLT."""

    template = rng.choice(TEMPLATES)
    return (
        template.format(
            rd=rng.choice(DATA_REGISTERS),
            rs1=rng.choice(REGISTERS),
            rs2=rng.choice(REGISTERS),
            byte=rng.randint(0, 0xFF),
            signed_byte=rng.randint(-0x80, 0x7F),
            offset=rng.randint(-0x10, 0xF),
            skip=rng.randint(0, min(SKIP_LIMIT, remaining)),
        )
        + "\n"
    )
