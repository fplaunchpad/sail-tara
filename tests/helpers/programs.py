"""The programs the emulators run: tests/programs, TARA Studio's examples, and the input lines
they run with."""

import random
from collections.abc import Callable
from pathlib import Path

from src.paths import PROGS_DIR

from tara.keys import ALL_KEYS, KeySchedule

# The `program` fixture: the image of a program in tests/programs, by name.
type ProgramImage = Callable[[str], Path]

PROGRAMS_DIRECTORY = Path(__file__).parents[1] / "programs"
PROGRAMS = sorted(PROGRAMS_DIRECTORY.glob("*.tara"))
EXAMPLES = sorted(Path(PROGS_DIR).rglob("*.tara"))
# Some examples never halt, and the OCaml emulator runs 15 to 30 thousand steps a second.
STEP_LIMIT = 30_000
# Retirements between changes of the input lines, which the games read.
KEY_PERIOD = 97


def program_id(source: Path) -> str:
    """A program's name in test ids: its directory and stem, as in Games/snake."""

    return f"{source.parent.name}/{source.stem}"


def key_schedule(seed: str) -> KeySchedule:
    """Input lines that change every KEY_PERIOD retirements up to STEP_LIMIT, seeded by `seed`."""

    rng = random.Random(seed)
    changes = tuple((step, rng.randint(0, ALL_KEYS)) for step in range(0, STEP_LIMIT, KEY_PERIOD))
    return KeySchedule(changes=changes)
