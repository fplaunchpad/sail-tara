"""Assemble TARA source with the TARA Studio assembler into a loadable image."""

from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import override

import click
from src.assembler.asm import AssemblerError, assemble

MEMORY_BYTES = 2048
WORD_BYTES = 2


class ImageFormat(StrEnum):
    """Loadable image encodings, named by their file suffix."""

    BIN = ".bin"
    HEX = ".hex"

    def render(self, words: Sequence[int]) -> bytes:
        """Encode instruction words, loaded from address 0, in this format."""

        match self:
            case ImageFormat.BIN:
                return b"".join(word.to_bytes(WORD_BYTES, "big") for word in words)
            case ImageFormat.HEX:
                return "".join(f"{word:04x}\n" for word in words).encode()


@dataclass(frozen=True)
class Image:
    """A loadable image file, encoded as its suffix says."""

    path: Path

    def __post_init__(self) -> None:
        if self.path.suffix not in ImageFormat:
            formats = " or ".join(ImageFormat)
            raise ValueError(f"{self.path}: expected a {formats} file")

    @property
    def format(self) -> ImageFormat:
        """The encoding selected by the file suffix."""

        return ImageFormat(self.path.suffix)

    def write(self, words: Sequence[int]) -> None:
        """Write instruction words, loaded from address 0, to this file."""

        self.path.write_bytes(self.format.render(words))


class ImageType(click.ParamType):
    """Converts a command-line path to an `Image`."""

    name = "image"

    @override
    def convert(
        self, value: Image | str, param: click.Parameter | None, ctx: click.Context | None
    ) -> Image:
        if isinstance(value, Image):
            return value

        try:
            return Image(Path(value))
        except ValueError as error:
            self.fail(str(error), param, ctx)


@dataclass(eq=False)
class AssemblyFailed(click.ClickException):
    """The assembler rejected `source`; `errors` keeps its diagnostics."""

    source: Path
    errors: tuple[AssemblerError, ...]

    def __post_init__(self) -> None:
        super().__init__("\n".join(f"{self.source}: {error}" for error in self.errors))


@dataclass(eq=False)
class ImageTooLarge(click.ClickException):
    """The assembled program does not fit in TARA memory."""

    source: Path
    size: int

    def __post_init__(self) -> None:
        super().__init__(f"{self.source}: {self.size} bytes exceed the {MEMORY_BYTES}-byte memory")


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


@click.command()
@click.argument("source", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option(
    "-o",
    "--output",
    type=ImageType(),
    help="Output image: .bin (bytes) or .hex (a word per line). Default: SOURCE.bin.",
)
def main(source: Path, output: Image | None) -> None:
    """Assemble SOURCE with the TARA Studio assembler into a loadable image."""

    image = output or Image(source.with_suffix(ImageFormat.BIN))
    image.write(assemble_file(source))


if __name__ == "__main__":
    main(prog_name="tara-asm")
