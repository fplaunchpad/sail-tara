"""The programs the emulators run: the test programs, the examples and TARA Studio's examples."""

from collections.abc import Callable
from pathlib import Path

from src.paths import PROGS_DIR

# The `program` fixture: the image of a test program, by name.
type Program = Callable[[str], Path]

ROOT = Path(__file__).parents[2]
PROGRAMS_DIRECTORY = ROOT / "tests" / "programs"
PROGRAMS = sorted(PROGRAMS_DIRECTORY.glob("*.tara"))
EXAMPLES_DIRECTORY = ROOT / "examples"
EXAMPLES = sorted(EXAMPLES_DIRECTORY.glob("*.tara"))
STUDIO_EXAMPLES = sorted(Path(PROGS_DIR).rglob("*.tara"))
# Some examples never halt, and the OCaml emulator runs 15 to 30 thousand steps a second.
STEP_LIMIT = 30_000
# Retirements between changes of the input lines, which the games read.
KEY_PERIOD = 97


def program_id(source: Path) -> str:
    """A program's name in test ids: its directory and stem, as in Games/snake."""

    return f"{source.parent.name}/{source.stem}"
