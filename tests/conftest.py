"""The emulators under test (`--emulator=PATH`, repeatable) and the programs they run.

Give the option with `=`: pytest reads a separate value as a test path before this file
registers the option."""

import difflib
import functools
from collections.abc import Callable
from pathlib import Path

import pytest

from tara.asm import assemble_file
from tara.emulator import Emulator
from tara.image import Image
from tara.transcript import Transcript

PROGRAMS = Path(__file__).parent / "programs"
# Each emulator's --disasm-all output, read once.
disassembly_of = functools.cache(Emulator.disassembly)


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
        metafunc.parametrize("emulator", emulators, ids=[emulator.name for emulator in emulators])


def pytest_assertrepr_compare(op: str, left: object, right: object) -> list[str] | None:
    if op == "==" and isinstance(left, Transcript) and isinstance(right, Transcript):
        diff = difflib.unified_diff(
            left.lines(memory_rows=True),
            right.lines(memory_rows=True),
            "emulator",
            "reference",
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


@pytest.fixture
def disassembly(emulator: Emulator) -> tuple[str, ...]:
    """The emulator's disassembly of every word: the model's assembly syntax, which the tests
    check against TARA Studio's assembler instead of re-implementing it."""

    return disassembly_of(emulator)


@pytest.fixture(scope="session")
def program(assemble: Callable[[Path], Path]) -> Callable[[str], Path]:
    """The image of a program in tests/programs, by name."""

    return lambda name: assemble(PROGRAMS / f"{name}.tara")
