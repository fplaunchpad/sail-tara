"""Render documentation tables from normalized Sail instruction metadata."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import click
import msgspec

from tara.table import (
    Alignment,
    Anchor,
    Cell,
    CellAlignment,
    Code,
    Column,
    Reference,
    Row,
    Table,
    Text,
)

type PositiveInt = Annotated[int, msgspec.Meta(gt=0)]
type NonEmptyString = Annotated[str, msgspec.Meta(min_length=1)]


class Field(msgspec.Struct, frozen=True, kw_only=True):
    name: NonEmptyString
    width: PositiveInt

    def __post_init__(self) -> None:
        if type(self.name) is not str or not self.name:
            raise ValueError("field name must not be empty")
        if type(self.width) is not int or self.width < 1:
            raise ValueError(f"{self.name}: field width must be a positive integer")


type NonEmptyFields = Annotated[list[Field], msgspec.Meta(min_length=1)]


class Instruction(msgspec.Struct, frozen=True, kw_only=True):
    constructor: NonEmptyString
    opcode_bits: NonEmptyString
    syntax: NonEmptyString
    fields: NonEmptyFields

    def __post_init__(self) -> None:
        if (
            type(self.constructor) is not str
            or not self.constructor
            or type(self.syntax) is not str
            or not self.syntax
        ):
            raise ValueError("instruction constructor and syntax must not be empty")
        if type(self.opcode_bits) is not str or not self.opcode_bits:
            raise ValueError(f"{self.constructor}: opcode_bits must not be empty")
        if not all(bit in "01" for bit in self.opcode_bits):
            raise ValueError(f"{self.constructor}: opcode_bits must be binary")
        if not self.fields:
            raise ValueError(f"{self.constructor}: fields must not be empty")
        if self.fields[0].name != "opcode":
            raise ValueError(f"{self.constructor}: first field must be opcode")
        if self.fields[0].width != len(self.opcode_bits):
            raise ValueError(f"{self.constructor}: opcode_bits and opcode field width differ")


type NonEmptyInstructions = Annotated[list[Instruction], msgspec.Meta(min_length=1)]


class Metadata(msgspec.Struct, frozen=True, kw_only=True):
    word_width: PositiveInt
    instructions: NonEmptyInstructions

    def __post_init__(self) -> None:
        if type(self.word_width) is not int or self.word_width < 1:
            raise ValueError("word_width must be a positive integer")
        if not self.instructions:
            raise ValueError("instructions must not be empty")

        constructors = [instruction.constructor for instruction in self.instructions]
        if len(constructors) != len(set(constructors)):
            raise ValueError("instructions contain duplicate constructors")

        opcodes = [instruction.opcode_bits for instruction in self.instructions]
        if len(opcodes) != len(set(opcodes)):
            raise ValueError("instructions contain duplicate opcodes")
        opcode_widths = {len(opcode) for opcode in opcodes}
        if len(opcode_widths) != 1:
            raise ValueError("instructions have inconsistent opcode widths")

        for instruction in self.instructions:
            field_width = sum(field.width for field in instruction.fields)
            if field_width != self.word_width:
                raise ValueError(
                    f"{instruction.constructor}: field widths total {field_width}, "
                    f"expected word width {self.word_width}"
                )


class MetadataError(click.ClickException):
    """The normalized metadata cannot describe consistent instruction tables."""


type FormatKey = tuple[tuple[str, int], ...]


def format_key(instruction: Instruction) -> FormatKey:
    return tuple((field.name, field.width) for field in instruction.fields)


def format_names(metadata: Metadata) -> dict[FormatKey, str]:
    keys = sorted({format_key(instruction) for instruction in metadata.instructions})
    return {key: f"F{index}" for index, key in enumerate(keys, start=1)}


def render_format_table(metadata: Metadata, names: dict[FormatKey, str]) -> str:
    columns = (
        Column(width=2, alignment=Alignment.LEFT),
        Column(repeat=metadata.word_width, alignment=Alignment.CENTERED),
        Column(width=5, alignment=Alignment.LEFT),
    )
    header = Row(
        cells=(
            Cell(content=(Text(value="Format"),)),
            *(
                Cell(content=(Text(value=str(bit)),))
                for bit in range(metadata.word_width - 1, -1, -1)
            ),
            Cell(content=(Text(value="Instructions"),)),
        )
    )
    rows = [header]

    for key, format_name in names.items():
        members = tuple(
            sorted(
                (
                    instruction
                    for instruction in metadata.instructions
                    if format_key(instruction) == key
                ),
                key=lambda item: int(item.opcode_bits, 2),
            )
        )
        cells = [Cell(content=(Anchor(identifier=f"fmt-{format_name}"), Text(value=format_name)))]
        for field_name, width in key:
            label = "0" * width if field_name == "padding" else field_name
            cells.append(
                Cell(
                    content=(Text(value=label),),
                    colspan=width,
                    alignment=CellAlignment.CENTERED,
                )
            )
        cells.append(Cell(content=(Text(value=", ".join(item.constructor for item in members)),)))
        rows.append(Row(cells=tuple(cells)))

    return Table(columns=columns, rows=tuple(rows)).to_asciidoc()


def render_opcode_table(metadata: Metadata, names: dict[FormatKey, str]) -> str:
    instructions = sorted(metadata.instructions, key=lambda item: int(item.opcode_bits, 2))
    opcode_width = len(instructions[0].opcode_bits)
    digits = (opcode_width + 3) // 4
    by_opcode = {int(item.opcode_bits, 2): item for item in instructions}
    missing = sorted(set(range(1 << opcode_width)) - by_opcode.keys())
    gaps: list[tuple[int, int]] = []
    for opcode in missing:
        if gaps and gaps[-1][1] == opcode - 1:
            gaps[-1] = (gaps[-1][0], opcode)
        else:
            gaps.append((opcode, opcode))

    columns = (
        Column(alignment=Alignment.CENTERED),
        Column(alignment=Alignment.CENTERED),
        Column(width=2, alignment=Alignment.CENTERED),
        Column(width=2),
        Column(width=4),
        Column(alignment=Alignment.CENTERED),
    )
    rows = [
        Row(
            cells=tuple(
                Cell(content=(Text(value=value),))
                for value in ("Opcode", "Hex", "Bits", "Mnemonic", "Syntax", "Format")
            )
        )
    ]
    gap_index = 0
    for opcode in range(1 << opcode_width):
        if instruction := by_opcode.get(opcode):
            format_name = names[format_key(instruction)]
            rows.append(
                Row(
                    cells=(
                        Cell(content=(Text(value=str(opcode)),)),
                        Cell(content=(Code(value=f"{opcode:0{digits}X}"),)),
                        Cell(content=(Code(value=instruction.opcode_bits),)),
                        Cell(
                            content=(
                                Reference(
                                    target=f"insn-{instruction.constructor}",
                                    content=(Code(value=instruction.constructor),),
                                ),
                            )
                        ),
                        Cell(content=(Code(value=instruction.syntax),)),
                        Cell(
                            content=(
                                Reference(
                                    target=f"fmt-{format_name}", content=(Text(value=format_name),)
                                ),
                            )
                        ),
                    )
                )
            )
        elif gap_index < len(gaps) and opcode == gaps[gap_index][0]:
            start, finish = gaps[gap_index]
            if start == finish:
                opcode_label = str(start)
                hex_range = (Code(value=f"{start:0{digits}X}"),)
                bit_range = (Code(value=f"{start:0{opcode_width}b}"),)
            else:
                opcode_label = f"{start}-{finish}"
                hex_range = (
                    Code(value=f"{start:0{digits}X}"),
                    Text(value="-"),
                    Code(value=f"{finish:0{digits}X}"),
                )
                bit_range = (
                    Code(value=f"{start:0{opcode_width}b}"),
                    Text(value="-"),
                    Code(value=f"{finish:0{opcode_width}b}"),
                )
            rows.append(
                Row(
                    cells=(
                        Cell(content=(Text(value=opcode_label),)),
                        Cell(content=hex_range),
                        Cell(content=bit_range),
                        Cell(content=(Text(value="unassigned"),), colspan=3),
                    )
                )
            )
            gap_index += 1

    return Table(columns=columns, rows=tuple(rows)).to_asciidoc()


def render_tables(metadata: Metadata) -> tuple[str, str]:
    names = format_names(metadata)
    formats = render_format_table(metadata, names)
    opcodes = render_opcode_table(metadata, names)
    return formats, opcodes


def write_tables(metadata_path: Path, output_directory: Path) -> None:
    try:
        metadata = msgspec.json.decode(metadata_path.read_bytes(), type=Metadata)
    except (OSError, msgspec.DecodeError, ValueError) as error:
        raise MetadataError(f"{metadata_path}: {error}") from error

    formats, opcodes = render_tables(metadata)
    output_directory.mkdir(parents=True, exist_ok=True)
    (output_directory / "formats.adoc").write_text(formats, encoding="utf-8")
    (output_directory / "opcodes.adoc").write_text(opcodes, encoding="utf-8")


@click.command()
@click.option(
    "--metadata",
    required=True,
    type=click.Path(path_type=Path, exists=True, dir_okay=False, readable=True),
)
@click.option(
    "--out",
    "output_directory",
    required=True,
    type=click.Path(path_type=Path, file_okay=False),
)
def main(metadata: Path, output_directory: Path) -> None:
    """Render format and opcode tables from normalized instruction metadata."""

    write_tables(metadata, output_directory)


if __name__ == "__main__":
    main()
