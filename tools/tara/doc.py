"""tara-doc: the specification's format table, opcode table and instruction sections, in
AsciiDoc, from the instruction metadata that the Sail plugin in tools/sail-doc derives from the
model's encode, decode and assembly definitions."""

import itertools
import math
import textwrap
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Self

import click
import msgspec

from tara.asciidoc import (
    Alignment,
    Anchor,
    Cell,
    CellAlignment,
    Code,
    Column,
    Inline,
    Link,
    Row,
    Table,
    Text,
)

PADDING = "padding"  # the plugin's name for bits that decoding ignores
HEX_DIGIT_BITS = 4
# A tint of the accent colour of styles.css and theme.yml; Asciidoctor takes only literal colours.
UNASSIGNED_BACKGROUND = "#F6DADF"
# The decode clause for the words of unassigned opcodes, with its description.
FALLBACK = """
include::sailcomment:decode[grep=None\\(,indent=0]

sail::decode[grep=None\\(]
"""
FORMATS = "formats.adoc"
OPCODES = "opcodes.adoc"
INSTRUCTIONS = "instructions.adoc"


class Field(msgspec.Struct, frozen=True, order=True, kw_only=True):
    """A field of an instruction word."""

    name: str
    width: int

    @property
    def label(self) -> str:
        """The field's name, or for padding its bits, which encoding clears."""

        return "0" * self.width if self.name == PADDING else self.name


class Instruction(msgspec.Struct, frozen=True, kw_only=True):
    """An instruction: its constructor, the model file that defines it, its operand count, its
    opcode, its assembly syntax and its fields, from the most significant bit."""

    constructor: str
    source_file: str
    operand_count: int
    opcode_bits: str
    syntax: str
    fields: tuple[Field, ...]

    @property
    def opcode(self) -> int:
        return int(self.opcode_bits, 2)

    @property
    def group(self) -> str:
        """The instruction's group, named after the file that defines it."""

        return Path(self.source_file).stem

    @property
    def anchor(self) -> str:
        return f"insn-{self.constructor}"

    def section(self) -> str:
        """The instruction's section: its description, and its encode, decode, execute and
        assembly clauses as the Sail Asciidoctor plugin includes them."""

        clause = f"{self.constructor}({', '.join(['_'] * self.operand_count)})"
        return textwrap.dedent(f"""\
            [#{self.anchor}%breakable]
            ==== `{self.constructor}`

            [.instruction%unbreakable]
            --

            include::sailcomment:execute[clause="{clause}",indent=0]

            sail::encode[clause="{clause}"]
            sail::decode[grep=Some\\({self.constructor}\\(]
            sail::execute[clause="{clause}"]
            sail::assembly[type=mapping,left-clause="{clause}"]

            --
            """)


@dataclass(frozen=True, kw_only=True)
class Format:
    """An instruction format: a layout of fields, and the instructions laid out so."""

    name: str
    fields: tuple[Field, ...]
    instructions: tuple[Instruction, ...]

    @property
    def anchor(self) -> str:
        return f"fmt-{self.name}"

    @property
    def placements(self) -> tuple[tuple[int, Field], ...]:
        """Each field, with the number of bits above it."""

        offsets = itertools.accumulate((field.width for field in self.fields[:-1]), initial=0)
        return tuple(zip(offsets, self.fields, strict=True))


class InstructionSet(msgspec.Struct, frozen=True, kw_only=True):
    """The instructions, by opcode, of an instruction set whose words are `word_width` bits."""

    word_width: int
    instructions: tuple[Instruction, ...]

    @classmethod
    def read(cls, path: Path) -> Self:
        return msgspec.json.decode(path.read_bytes(), type=cls)

    def formats(self) -> list[Format]:
        """The formats, named F1, F2 and so on in the order of their fields' names and widths."""

        layouts = sorted({instruction.fields for instruction in self.instructions})
        return [
            Format(
                name=f"F{number}",
                fields=fields,
                instructions=tuple(
                    instruction for instruction in self.instructions if instruction.fields == fields
                ),
            )
            for number, fields in enumerate(layouts, start=1)
        ]

    def format_table(self) -> Table:
        """A row per format, a column per bit. A field that sits at the same bits in the next
        format spans its row too."""

        formats = self.formats()
        placements = [set(format.placements) for format in formats]
        rows: list[Row] = []
        for index, format in enumerate(formats):
            cells = [Cell(content=(Anchor(format.anchor), Text(format.name)))]
            for placement in format.placements:
                if index > 0 and placement in placements[index - 1]:
                    continue  # the field's cell in the row above spans this row

                rows_spanned = 1
                for below in placements[index + 1 :]:
                    if placement not in below:
                        break

                    rows_spanned += 1

                _offset, field = placement
                cells.append(
                    Cell(
                        content=(Code(field.label),),
                        columns=field.width,
                        rows=rows_spanned,
                        alignment=CellAlignment.CENTER,
                    )
                )

            names = ", ".join(instruction.constructor for instruction in format.instructions)
            rows.append(Row(cells=(*cells, Cell(content=(Code(names),)))))

        return Table(
            columns=(
                Column(width=2, alignment=Alignment.CENTER),
                Column(width=1, alignment=Alignment.CENTER, repeat=self.word_width),
                Column(width=5, alignment=Alignment.LEFT),
            ),
            header=("Format", *map(str, reversed(range(self.word_width))), "Instructions"),
            rows=tuple(rows),
            width=92,
        )

    @property
    def opcode_width(self) -> int:
        return len(self.instructions[0].opcode_bits)

    def opcodes(self) -> str:
        """The opcode table, and the decode clause for unassigned opcodes if there are any."""

        table = str(self.opcode_table())
        return table if len(self.instructions) == 1 << self.opcode_width else table + FALLBACK

    def opcode_table(self) -> Table:
        """A row per opcode, and one per run of unassigned opcodes."""

        opcode_width = self.opcode_width
        digits = math.ceil(opcode_width / HEX_DIGIT_BITS)
        formats = {
            instruction.constructor: format
            for format in self.formats()
            for instruction in format.instructions
        }
        by_opcode = {instruction.opcode: instruction for instruction in self.instructions}
        rows: list[Row] = []
        for assigned, run in itertools.groupby(range(1 << opcode_width), by_opcode.__contains__):
            opcodes = list(run)
            if assigned:
                for opcode in opcodes:
                    instruction = by_opcode[opcode]
                    format = formats[instruction.constructor]
                    rows.append(
                        Row(
                            cells=(
                                Cell(content=(Text(str(opcode)),)),
                                Cell(content=(Code(f"{opcode:0{digits}X}"),)),
                                Cell(content=(Code(instruction.opcode_bits),)),
                                Cell(
                                    content=(
                                        Link(
                                            target=instruction.anchor,
                                            content=Code(instruction.constructor),
                                        ),
                                    ),
                                    alignment=CellAlignment.CENTER,
                                ),
                                Cell(content=(Code(instruction.syntax),)),
                                Cell(
                                    content=(Link(target=format.anchor, content=Text(format.name)),)
                                ),
                            )
                        )
                    )

                continue

            ends = sorted({opcodes[0], opcodes[-1]})
            rows.append(
                Row(
                    cells=(
                        Cell(content=(Text("-".join(map(str, ends))),)),
                        Cell(content=dashed([f"{opcode:0{digits}X}" for opcode in ends])),
                        Cell(content=dashed([f"{opcode:0{opcode_width}b}" for opcode in ends])),
                        Cell(
                            content=(Text("unassigned"),),
                            columns=3,
                            alignment=CellAlignment.CENTER,
                        ),
                    ),
                    background=UNASSIGNED_BACKGROUND,
                )
            )

        return Table(
            columns=(
                Column(width=2, alignment=Alignment.CENTER),
                Column(width=2, alignment=Alignment.CENTER),
                Column(width=4, alignment=Alignment.CENTER),
                Column(width=3),
                Column(width=5),
                Column(width=2, alignment=Alignment.CENTER),
            ),
            header=("Opcode", "Hex", "Bits", "Mnemonic", "Syntax", "Format"),
            rows=tuple(rows),
            width=72,
        )

    def sections(self) -> str:
        """The instruction sections, a group at a time. Each group opens with the `section_<group>`
        and `<group>` anchors of the file that defines it."""

        groups: dict[str, list[Instruction]] = {}
        for instruction in self.instructions:
            groups.setdefault(instruction.group, []).append(instruction)

        blocks: list[str] = []
        for group, instructions in groups.items():
            blocks += [
                f"include::sailcomment:{anchor}[type=anchor,indent=0]\n"
                for anchor in (f"section_{group}", group)
            ]
            blocks += [instruction.section() for instruction in instructions]

        return "\n".join(blocks)


def dashed(spellings: Sequence[str]) -> tuple[Inline, ...]:
    """Each of `spellings` as code, with a dash between them."""

    inlines: list[Inline] = [Code(spellings[0])]
    for spelling in spellings[1:]:
        inlines += [Text("-"), Code(spelling)]

    return tuple(inlines)


@click.command()
@click.argument("metadata", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.argument("directory", type=click.Path(file_okay=False, path_type=Path))
def main(metadata: Path, directory: Path) -> None:
    """Write the format table, the opcode table and the instruction sections of the instruction
    set that METADATA describes into DIRECTORY."""

    instruction_set = InstructionSet.read(metadata)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / FORMATS).write_text(str(instruction_set.format_table()))
    (directory / OPCODES).write_text(instruction_set.opcodes())
    (directory / INSTRUCTIONS).write_text(instruction_set.sections())


if __name__ == "__main__":
    main(prog_name="tara-doc")
