"""The emulators under test (`--emulator=PATH`, repeatable) and the programs they run.

Give the option with `=`: pytest reads a separate value as a test path before this file
registers the option."""

import difflib
import functools
from collections.abc import Callable, Iterator
from pathlib import Path

import pytest
from hypothesis import settings

from helpers.programs import PROGRAMS_DIRECTORY, ProgramImage
from helpers.terminal import Session, Start
from tara.asm import assemble_file
from tara.emulator import Emulator
from tara.image import Image
from tara.transcript import Transcript

# Each random program runs the emulator, so examples are few and have no deadline. The ci profile
# (--hypothesis-profile=ci) draws the same examples on every run and keeps no database.
settings.register_profile("dev", max_examples=50, deadline=None)
settings.register_profile("ci", parent=settings.get_profile("dev"), derandomize=True, database=None)
settings.load_profile("dev")


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--emulator",
        action="append",
        default=[],
        type=Path,
        metavar="PATH",
        help="An emulator executable to test; repeat the option to test several.",
    )


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "emulator" in metafunc.fixturenames:
        paths = metafunc.config.getoption("emulator") or list[Path]()
        emulators = [Emulator(Path(path)) for path in paths]
        metafunc.parametrize(
            "emulator", emulators, ids=[emulator.name for emulator in emulators], scope="session"
        )


def pytest_assertrepr_compare(op: str, left: object, right: object) -> list[str] | None:
    if op == "==" and isinstance(left, Transcript) and isinstance(right, Transcript):
        diff = difflib.unified_diff(
            left.lines(memory_rows=True),
            right.lines(memory_rows=True),
            fromfile="emulator",
            tofile="reference",
            lineterm="",
        )
        return ["the emulator's output differs from the reference model's:", *diff]

    return None


@pytest.fixture(scope="session")
def assemble(tmp_path_factory: pytest.TempPathFactory) -> Callable[[Path], Path]:
    """Assembles a .tara source into a .bin image, once per session."""

    directory = tmp_path_factory.mktemp("images")

    @functools.cache
    def assemble(source: Path) -> Path:
        image = Image(directory / f"{source.parent.name}-{source.stem}.bin")
        image.write(assemble_file(source))
        return image.path

    return assemble


@pytest.fixture(scope="session")
def disassembly(emulator: Emulator) -> tuple[str, ...]:
    """The emulator's disassembly of every word: the model's assembly syntax, which the tests
    check against TARA Studio's assembler instead of re-implementing it."""

    return emulator.disassembly()


@pytest.fixture(scope="session")
def scratch(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """A directory for files that each Hypothesis example overwrites."""

    return tmp_path_factory.mktemp("scratch")


@pytest.fixture(scope="session")
def program(assemble: Callable[[Path], Path]) -> ProgramImage:
    """The image of a program in tests/programs, by name."""

    return lambda name: assemble(PROGRAMS_DIRECTORY / f"{name}.tara")


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
