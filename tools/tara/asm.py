"""tara-asm: assemble TARA source with TARA Studio's assembler into a loadable image."""

from dataclasses import dataclass
from pathlib import Path
from typing import override

import click
from src.assembler.asm import AssemblerError, assemble

from tara.image import Image, ImageFormat
from tara.isa import MEMORY_BYTES, WORD_BYTES


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


@dataclass(eq=False, kw_only=True)
class AssemblyFailed(click.ClickException):
    """The assembler rejected `source`."""

    source: Path
    errors: tuple[AssemblerError, ...]

    def __post_init__(self) -> None:
        super().__init__("\n".join(f"{self.source}: {error}" for error in self.errors))


@dataclass(eq=False, kw_only=True)
class ImageTooLarge(click.ClickException):
    """The program in `source` does not fit in memory."""

    source: Path
    size: int

    def __post_init__(self) -> None:
        super().__init__(f"{self.source}: {self.size} bytes exceed the {MEMORY_BYTES}-byte memory")


def assemble_file(source: Path) -> list[int]:
    """The words of the program in `source`, from address 0."""

    placed, _listing, errors, _labels = assemble(source.read_text())
    if errors:
        raise AssemblyFailed(source=source, errors=tuple(errors))

    words = [word for _address, word in placed]
    if (size := len(words) * WORD_BYTES) > MEMORY_BYTES:
        raise ImageTooLarge(source=source, size=size)

    return words


@click.command()
@click.argument("source", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option(
    "-o",
    "--output",
    type=ImageType(),
    help="Output image: .bin (bytes) or .hex (a word per line). Default: SOURCE.bin.",
)
def main(source: Path, output: Image | None) -> None:
    """Assemble SOURCE with TARA Studio's assembler into a loadable image."""

    image = output or Image(source.with_suffix(ImageFormat.BIN))
    image.write(assemble_file(source))


if __name__ == "__main__":
    main(prog_name="tara-asm")
