"""tara-doc: the specification's format table, opcode or encoding table and instruction sections,
in AsciiDoc, from the instruction metadata that the Sail plugin in tools/sail-doc reads from the
model."""

import itertools
import math
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum, auto
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

OPCODE = "opcode"  # the label of fixed bits that the model leaves unnamed
HEX_DIGIT_BITS = 4
# A tint of the accent colour of styles.css and theme.yml; Asciidoctor takes only literal colours.
UNASSIGNED_BACKGROUND = "#F6DADF"
FORMATS = "formats.adoc"
OPCODES = "opcodes.adoc"
INSTRUCTIONS = "instructions.adoc"

type Slot = tuple[str, int]


class Fixed(msgspec.Struct, frozen=True, tag="fixed", tag_field="kind"):
    """Bits that an instruction's decode clause fixes, with the name the model gives them."""

    name: str | None
    bits: str

    @property
    def width(self) -> int:
        return len(self.bits)

    @property
    def label(self) -> str:
        return self.name or OPCODE

    @property
    def pattern(self) -> str:
        return self.bits


class Operand(msgspec.Struct, frozen=True, tag="operand", tag_field="kind"):
    """Bits that a decode clause binds to a name."""

    name: str
    width: int

    @property
    def label(self) -> str:
        return self.name

    @property
    def pattern(self) -> str:
        return "x" * self.width


class Ignored(msgspec.Struct, frozen=True, tag="ignored", tag_field="kind"):
    """Bits that a decode clause ignores."""

    width: int

    @property
    def label(self) -> str:
        return "0" * self.width

    @property
    def pattern(self) -> str:
        return "-" * self.width


type Field = Fixed | Operand | Ignored


class Selector(StrEnum):
    """How the Sail Asciidoctor plugin finds a clause: by the constructor that its pattern takes
    apart or its body builds, or by the constructor on the left or the right of a mapping
    clause."""

    PATTERN = auto()
    BODY = auto()
    LEFT = auto()
    RIGHT = auto()


class Clause(msgspec.Struct, frozen=True):
    """An instruction's clause of the function or mapping `function`."""

    function: str
    selector: Selector
    documented: bool

    def attributes(self, instruction: Instruction) -> str:
        """The attributes that select this clause of `instruction`."""

        match self.selector:
            case Selector.PATTERN:
                return f'clause="{instruction.pattern}"'
            case Selector.BODY:
                return f"grep=\\b{instruction.constructor}\\("
            case Selector.LEFT:
                return f'type=mapping,left-clause="{instruction.pattern}"'
            case Selector.RIGHT:
                return f'type=mapping,right-clause="{instruction.pattern}"'


class Instruction(msgspec.Struct, frozen=True, kw_only=True):
    """An instruction: its constructor, its assembly syntax, the fields of its word from the most
    significant bit, and the clauses that handle it, in source order."""

    constructor: str
    operand_count: int
    syntax: str
    fields: tuple[Field, ...]
    clauses: tuple[Clause, ...]

    @property
    def anchor(self) -> str:
        return f"insn-{self.constructor}"

    @property
    def pattern(self) -> str:
        """The pattern that takes the instruction apart, with wildcards for its operands."""

        return f"{self.constructor}({', '.join(['_'] * self.operand_count)})"

    @property
    def encoding(self) -> str:
        """The word with the fixed bits in place, `x` for operands and `-` for ignored bits."""

        return "".join(field.pattern for field in self.fields)

    @property
    def layout(self) -> tuple[Slot, ...]:
        return tuple((field.label, field.width) for field in self.fields)

    def section(self, *, level: int) -> str:
        """The instruction's section: the comments of its documented clauses, then every clause,
        as the Sail Asciidoctor plugin includes them."""

        lines = [
            f"[#{self.anchor}%breakable]",
            f"{'=' * level} `{self.constructor}`",
            "",
            "[.instruction%unbreakable]",
            "--",
            "",
        ]
        for clause in self.clauses:
            if clause.documented:
                lines += [
                    f"include::sailcomment:{clause.function}[{clause.attributes(self)},indent=0]",
                    "",
                ]

        lines += [f"sail::{clause.function}[{clause.attributes(self)}]" for clause in self.clauses]
        lines += ["", "--", ""]
        return "\n".join(lines)


class AnchorEntry(msgspec.Struct, frozen=True, tag="anchor", tag_field="kind"):
    name: str


class InstructionEntry(msgspec.Struct, frozen=True, tag="instruction", tag_field="kind"):
    name: str


class Fallback(msgspec.Struct, frozen=True):
    """The clause of the function `function` that decodes the words of no instruction."""

    function: str
    documented: bool

    def listing(self) -> str:
        lines = [f"include::sailcomment:{self.function}[grep=None\\(,indent=0]", ""]
        lines = [*(lines if self.documented else []), f"sail::{self.function}[grep=None\\(]"]
        return "".join(f"\n{line}" for line in lines) + "\n"


@dataclass(frozen=True, kw_only=True)
class Format:
    """An instruction format: a layout of fields, and the instructions laid out so."""

    name: str
    layout: tuple[Slot, ...]
    instructions: tuple[Instruction, ...]

    @property
    def anchor(self) -> str:
        return f"fmt-{self.name}"

    @property
    def placements(self) -> tuple[tuple[int, Slot], ...]:
        """Each field, with the number of bits above it."""

        offsets = itertools.accumulate((width for _label, width in self.layout[:-1]), initial=0)
        return tuple(zip(offsets, self.layout, strict=True))


class InstructionSet(msgspec.Struct, frozen=True, kw_only=True):
    """The instructions of an instruction set whose words are `word_width` bits, and the outline
    of the files that define them: their documented anchors and instructions, in source order."""

    word_width: int
    instructions: tuple[Instruction, ...]
    outline: tuple[AnchorEntry | InstructionEntry, ...]
    fallback: Fallback

    @classmethod
    def read(cls, path: Path) -> Self:
        return msgspec.json.decode(path.read_bytes(), type=cls)

    @property
    def by_encoding(self) -> list[Instruction]:
        return sorted(self.instructions, key=lambda instruction: instruction.encoding)

    @property
    def opcode_width(self) -> int | None:
        """The width of the opcode, if a single leading field of fixed bits of one width tells the
        instructions apart; None if they are told apart otherwise."""

        widths: set[int] = set()
        for instruction in self.instructions:
            first, *rest = instruction.fields
            if not isinstance(first, Fixed) or any(isinstance(field, Fixed) for field in rest):
                return None

            widths.add(first.width)

        return widths.pop() if len(widths) == 1 else None

    def formats(self) -> list[Format]:
        """The formats, named F1, F2 and so on in the order of their first encodings. A format added
        for an encoding above the assigned ones takes the next number, leaving the others alone."""

        layouts = dict.fromkeys(instruction.layout for instruction in self.by_encoding)
        return [
            Format(
                name=f"F{number}",
                layout=layout,
                instructions=tuple(
                    instruction for instruction in self.by_encoding if instruction.layout == layout
                ),
            )
            for number, layout in enumerate(layouts, start=1)
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

                _offset, (label, width) = placement
                cells.append(
                    Cell(
                        content=(Code(label),),
                        columns=width,
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

    def opcodes(self) -> str:
        """The opcode table if a leading opcode tells the instructions apart, with the decode
        clause for unassigned opcodes if there are any; otherwise the encoding table and that
        clause."""

        width = self.opcode_width
        if width is None:
            return str(self.encoding_table()) + self.fallback.listing()

        table = str(self.opcode_table(width))
        return table if len(self.instructions) == 1 << width else table + self.fallback.listing()

    def opcode_table(self, width: int) -> Table:
        """A row per opcode of `width` bits, and one per run of unassigned opcodes."""

        digits = math.ceil(width / HEX_DIGIT_BITS)
        formats = self.format_names()
        by_opcode = {
            int(instruction.encoding[:width], 2): instruction for instruction in self.instructions
        }
        rows: list[Row] = []
        for assigned, run in itertools.groupby(range(1 << width), by_opcode.__contains__):
            opcodes = list(run)
            if assigned:
                rows += [
                    Row(
                        cells=(
                            Cell(content=(Text(str(opcode)),)),
                            Cell(content=(Code(f"{opcode:0{digits}X}"),)),
                            Cell(content=(Code(f"{opcode:0{width}b}"),)),
                            *self.description(by_opcode[opcode], formats),
                        )
                    )
                    for opcode in opcodes
                ]
                continue

            ends = sorted({opcodes[0], opcodes[-1]})
            rows.append(
                Row(
                    cells=(
                        Cell(content=(Text("-".join(map(str, ends))),)),
                        Cell(content=dashed([f"{opcode:0{digits}X}" for opcode in ends])),
                        Cell(content=dashed([f"{opcode:0{width}b}" for opcode in ends])),
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

    def encoding_table(self) -> Table:
        """A row per instruction, by encoding: its fixed bits, `x` for operand bits and `-` for
        ignored bits, a field at a time."""

        formats = self.format_names()
        rows = tuple(
            Row(
                cells=(
                    Cell(content=(Code(" ".join(field.pattern for field in instruction.fields)),)),
                    *self.description(instruction, formats),
                )
            )
            for instruction in self.by_encoding
        )
        return Table(
            columns=(
                Column(width=6, alignment=Alignment.CENTER),
                Column(width=3),
                Column(width=5),
                Column(width=2, alignment=Alignment.CENTER),
            ),
            header=("Encoding", "Mnemonic", "Syntax", "Format"),
            rows=rows,
            width=92,
        )

    def format_names(self) -> dict[str, Format]:
        return {
            instruction.constructor: format
            for format in self.formats()
            for instruction in format.instructions
        }

    @staticmethod
    def description(instruction: Instruction, formats: dict[str, Format]) -> tuple[Cell, ...]:
        """An instruction's mnemonic, syntax and format cells."""

        format = formats[instruction.constructor]
        return (
            Cell(
                content=(Link(target=instruction.anchor, content=Code(instruction.constructor)),),
                alignment=CellAlignment.CENTER,
            ),
            Cell(content=(Code(instruction.syntax),)),
            Cell(content=(Link(target=format.anchor, content=Text(format.name)),)),
        )

    def sections(self, *, level: int) -> str:
        """The outline: each documented anchor of the files that define instructions, and each
        instruction's section at heading `level`, in source order."""

        by_constructor = {instruction.constructor: instruction for instruction in self.instructions}
        blocks: list[str] = []
        for entry in self.outline:
            match entry:
                case AnchorEntry(name=name):
                    blocks.append(f"include::sailcomment:{name}[type=anchor,indent=0]\n")
                case InstructionEntry(name=name):
                    blocks.append(by_constructor[name].section(level=level))

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
@click.option(
    "--section-level",
    type=click.IntRange(1, 5),
    default=4,
    show_default=True,
    help="The heading level of each instruction's section.",
)
def main(metadata: Path, directory: Path, section_level: int) -> None:
    """Write the format table, the opcode or encoding table and the instruction sections of the
    instruction set that METADATA describes into DIRECTORY."""

    instruction_set = InstructionSet.read(metadata)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / FORMATS).write_text(str(instruction_set.format_table()))
    (directory / OPCODES).write_text(instruction_set.opcodes())
    (directory / INSTRUCTIONS).write_text(instruction_set.sections(level=section_level))


if __name__ == "__main__":
    main(prog_name="tara-doc")
