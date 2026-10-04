"""Assemble TARA source with the TARA Studio assembler into a loadable image."""

import argparse
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from src.assembler.asm import AssemblerError, assemble

MEMORY_BYTES = 2048
WORD_BYTES = 2


class ImageFormat(StrEnum):
    """Loadable image encodings, named by their file suffix."""

    BIN = ".bin"
    HEX = ".hex"

    @classmethod
    def of(cls, path: Path) -> ImageFormat:
        """Return the format selected by `path`'s suffix."""

        return cls(path.suffix)

    def render(self, words: Sequence[int]) -> bytes:
        """Encode instruction words, loaded from address 0, in this format."""

        match self:
            case ImageFormat.BIN:
                return b"".join(word.to_bytes(WORD_BYTES, "big") for word in words)
            case ImageFormat.HEX:
                return "".join(f"{word:04x}\n" for word in words).encode()


@dataclass(eq=False)
class AssemblyFailed(Exception):
    """The assembler rejected `source`; `errors` keeps its diagnostics."""

    source: Path
    errors: tuple[AssemblerError, ...]


@dataclass(eq=False)
class ImageTooLarge(Exception):
    """The assembled program does not fit in TARA memory."""

    source: Path
    size: int


def assemble_file(source: Path) -> list[int]:
    """Assemble `source` and return its words in address order from 0."""

    placed, _listing, errors, _labels = assemble(source.read_text(encoding="utf-8"))
    if errors:
        raise AssemblyFailed(source, tuple(errors))

    size = len(placed) * WORD_BYTES
    if size > MEMORY_BYTES:
        raise ImageTooLarge(source, size)

    for index, (address, _word) in enumerate(placed):
        if address != index * WORD_BYTES:
            raise AssertionError(f"assembler placed word {index} at {address:#06x}")

    return [word for _address, word in placed]


def image_path(value: str) -> Path:
    """Validate an output path whose suffix names a supported image format."""

    path = Path(value)
    try:
        ImageFormat.of(path)
    except ValueError:
        formats = ", ".join(ImageFormat)
        raise argparse.ArgumentTypeError(f"{value}: expected one of {formats}") from None

    return path


def main(argv: Sequence[str] | None = None) -> int:
    """Run the `tara-asm` command."""

    parser = argparse.ArgumentParser(prog="tara-asm", description=__doc__)
    parser.add_argument("source", type=Path, help="TARA assembly (.tara/.asm)")
    parser.add_argument(
        "-o", "--output", type=image_path, help="output image (.bin or .hex; default: SOURCE.bin)"
    )
    arguments = parser.parse_args(argv)
    source: Path = arguments.source
    output: Path = arguments.output or source.with_suffix(ImageFormat.BIN)

    try:
        words = assemble_file(source)
    except AssemblyFailed as failure:
        for error in failure.errors:
            print(f"{failure.source}: {error}", file=sys.stderr)
        return 1
    except ImageTooLarge as failure:
        print(f"{failure.source}: {failure.size} bytes exceed {MEMORY_BYTES}", file=sys.stderr)
        return 1

    output.write_bytes(ImageFormat.of(output).render(words))
    return 0


if __name__ == "__main__":
    sys.exit(main())
