"""tara-doc: the specification's format table, opcode or encoding table and instruction sections,
in AsciiDoc, from the instruction metadata that the Sail plugin in tools/sail-doc reads from the
model."""

import itertools
import re
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
    LineBreak,
    Link,
    Row,
    Table,
    Text,
)

# A tint of the accent colour of styles.css and theme.yml; Asciidoctor takes only literal colours.
UNASSIGNED_BACKGROUND = "#F6DADF"
MNEMONIC = re.compile(r"[\w.]+")
FORMATS = "formats.adoc"
OPCODES = "opcodes.adoc"
INSTRUCTIONS = "instructions.adoc"

type Slot = tuple[str, int]


class Fixed(msgspec.Struct, frozen=True, tag="fixed", tag_field="kind"):
    """Bits that an instruction's encoding fixes, with the name of the type that annotates
    them."""

    name: str | None
    bits: str

    @property
    def width(self) -> int:
        return len(self.bits)

    @property
    def label(self) -> str:
        return self.name or ""

    @property
    def pattern(self) -> str:
        return self.bits


class Operand(msgspec.Struct, frozen=True, tag="operand", tag_field="kind"):
    """Bits that an encoding binds to a name."""

    name: str
    width: int

    @property
    def label(self) -> str:
        return self.name

    @property
    def pattern(self) -> str:
        return "x" * self.width


class Ignored(msgspec.Struct, frozen=True, tag="ignored", tag_field="kind"):
    """Bits that an encoding ignores."""

    width: int

    @property
    def label(self) -> str:
        return self.pattern

    @property
    def pattern(self) -> str:
        return "-" * self.width


type Field = Fixed | Operand | Ignored


def section_anchor(constructor: str) -> str:
    return f"insn-{constructor}"


class Instruction(msgspec.Struct, frozen=True, kw_only=True):
    """An instruction: its constructor, its assembly syntax, the fields of its word from the most
    significant bit, the condition its encoding is guarded by, and the statements that carry it
    out, as the model writes them."""

    constructor: str
    syntax: str
    fields: tuple[Field, ...]
    condition: str | None
    execution: tuple[str, ...]

    @property
    def mnemonic(self) -> str:
        match = MNEMONIC.match(self.syntax)
        return match.group() if match else self.syntax

    @property
    def encoding(self) -> str:
        """The word with the fixed bits in place, `x` for operands and `-` for ignored bits."""

        return "".join(field.pattern for field in self.fields)

    @property
    def layout(self) -> tuple[Slot, ...]:
        return tuple((field.label, field.width) for field in self.fields)

    def condition_cell(self) -> Cell:
        return Cell(content=(Code(" ".join(self.condition.split())),) if self.condition else ())

    def cells(self, format: Format) -> tuple[Cell, ...]:
        """The instruction's syntax, linked to its section, its execution, a statement a line, and
        its format."""

        execution: list[Inline] = []
        for statement in self.execution:
            execution += [*([LineBreak()] if execution else []), Code(" ".join(statement.split()))]

        return (
            Cell(
                content=(Link(target=section_anchor(self.constructor), content=Code(self.syntax)),)
            ),
            Cell(content=tuple(execution)),
            Cell(content=(Link(target=format.anchor, content=Text(format.name)),)),
        )


class Selector(StrEnum):
    """How the Sail Asciidoctor plugin finds a clause: by the pattern of a function clause, or by
    the left or the right of a mapping clause."""

    PATTERN = auto()
    LEFT = auto()
    RIGHT = auto()


class Clause(msgspec.Struct, frozen=True):
    """A clause of the function or mapping `function` that takes a constructor apart, which the
    Sail Asciidoctor plugin finds by `pattern`."""

    function: str
    selector: Selector
    pattern: str
    documented: bool

    @property
    def attributes(self) -> str:
        match self.selector:
            case Selector.PATTERN:
                return f'clause="{self.pattern}"'
            case Selector.LEFT:
                return f'type=mapping,left-clause="{self.pattern}"'
            case Selector.RIGHT:
                return f'type=mapping,right-clause="{self.pattern}"'


class AnchorEntry(msgspec.Struct, frozen=True, tag="anchor", tag_field="kind"):
    name: str

    def section(self) -> str:
        return f"include::sailcomment:{self.name}[type=anchor,indent=0]\n"


class ConstructorEntry(msgspec.Struct, frozen=True, tag="constructor", tag_field="kind"):
    """An instruction constructor and the clauses that take it apart, in source order."""

    name: str
    clauses: tuple[Clause, ...]

    def section(self, *, level: int) -> str:
        """The constructor's section: the comments of its documented clauses, then every clause,
        as the Sail Asciidoctor plugin includes them."""

        lines = [
            f"[#{section_anchor(self.name)}%breakable]",
            f"{'=' * level} `{self.name}`",
            "",
            "[.instruction%unbreakable]",
            "--",
            "",
        ]
        for clause in self.clauses:
            if clause.documented:
                lines += [
                    f"include::sailcomment:{clause.function}[{clause.attributes},indent=0]",
                    "",
                ]

        lines += [f"sail::{clause.function}[{clause.attributes}]" for clause in self.clauses]
        lines += ["", "--", ""]
        return "\n".join(lines)


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
    of the files that define them: their documented anchors and constructors, in source order."""

    word_width: int
    instructions: tuple[Instruction, ...]
    outline: tuple[AnchorEntry | ConstructorEntry, ...]

    @classmethod
    def read(cls, path: Path) -> Self:
        return msgspec.json.decode(path.read_bytes(), type=cls)

    @property
    def by_encoding(self) -> list[Instruction]:
        return sorted(self.instructions, key=lambda instruction: instruction.encoding)

    @property
    def opcode_width(self) -> int | None:
        """The width of the opcode, if a single leading field of fixed bits of one width tells the
        instructions apart and no encoding is guarded; None if they are told apart otherwise."""

        widths: set[int] = set()
        for instruction in self.instructions:
            first, *rest = instruction.fields
            if (
                not isinstance(first, Fixed)
                or any(isinstance(field, Fixed) for field in rest)
                or instruction.condition is not None
            ):
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

    def format_of(self) -> dict[Instruction, Format]:
        return {
            instruction: format for format in self.formats() for instruction in format.instructions
        }

    def format_table(self) -> Table:
        """A row per format, and a column per run of bits that no format splits, headed by the
        numbers of its first and last bits. A field that sits at the same bits in the next format
        spans its row too."""

        formats = self.formats()
        placements = [set(format.placements) for format in formats]
        boundaries = sorted(
            {0, self.word_width}
            | {offset + width for format in formats for offset, (_, width) in format.placements}
            | {offset for format in formats for offset, _slot in format.placements}
        )
        runs = list(itertools.pairwise(boundaries))
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

                offset, (label, width) = placement
                cells.append(
                    Cell(
                        content=(Code(label),) if label else (),
                        columns=boundaries.index(offset + width) - boundaries.index(offset),
                        rows=rows_spanned,
                        alignment=CellAlignment.CENTER,
                    )
                )

            mnemonics = ", ".join(instruction.mnemonic for instruction in format.instructions)
            rows.append(Row(cells=(*cells, Cell(content=(Code(mnemonics),)))))

        return Table(
            columns=(
                Column(width=2, alignment=Alignment.CENTER),
                *(Column(width=end - start, alignment=Alignment.CENTER) for start, end in runs),
                Column(width=5, alignment=Alignment.LEFT),
            ),
            header=("Format", *(self.bit_range(start, end) for start, end in runs), "Instructions"),
            rows=tuple(rows),
            width=92,
        )

    def bit_range(self, start: int, end: int) -> str:
        """The numbers of the first and last bits of the run of bits `start` to `end` from the
        top of the word, most significant first."""

        first, last = self.word_width - 1 - start, self.word_width - end
        return str(first) if first == last else f"{first}\u2013{last}"

    def opcodes(self) -> Table:
        """The opcode table if a leading opcode tells the instructions apart, and otherwise the
        encoding table."""

        width = self.opcode_width
        return self.encoding_table() if width is None else self.opcode_table(width)

    def opcode_table(self, width: int) -> Table:
        """A row per opcode of `width` bits, and one per run of unassigned opcodes."""

        format_of = self.format_of()
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
                            *by_opcode[opcode].cells(format_of[by_opcode[opcode]]),
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
                Column(width=5),
                Column(width=10),
                Column(width=2, alignment=Alignment.CENTER),
            ),
            header=("Opcode", "Syntax", "Execution", "Format"),
            rows=tuple(rows),
            width=100,
        )

    def encoding_table(self) -> Table:
        """A row per instruction, by encoding: its fixed bits, `x` for operand bits and `-` for
        ignored bits, a field at a time, and the condition it is guarded by if any is."""

        format_of = self.format_of()
        guarded = any(instruction.condition is not None for instruction in self.instructions)
        rows = tuple(
            Row(
                cells=(
                    Cell(content=(Code(" ".join(field.pattern for field in instruction.fields)),)),
                    *([instruction.condition_cell()] if guarded else []),
                    *instruction.cells(format_of[instruction]),
                )
            )
            for instruction in self.by_encoding
        )
        return Table(
            columns=(
                Column(width=6, alignment=Alignment.CENTER),
                *([Column(width=3)] if guarded else []),
                Column(width=5),
                Column(width=8),
                Column(width=2, alignment=Alignment.CENTER),
            ),
            header=(
                "Encoding",
                *(["Condition"] if guarded else []),
                "Syntax",
                "Execution",
                "Format",
            ),
            rows=rows,
            width=100,
        )

    def sections(self, *, level: int) -> str:
        """The outline: each documented anchor of the files that define instructions, and each
        constructor's section at heading `level`, in source order."""

        return "\n".join(
            entry.section() if isinstance(entry, AnchorEntry) else entry.section(level=level)
            for entry in self.outline
        )


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
    (directory / OPCODES).write_text(str(instruction_set.opcodes()))
    (directory / INSTRUCTIONS).write_text(instruction_set.sections(level=section_level))


if __name__ == "__main__":
    main(prog_name="tara-doc")
