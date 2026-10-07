"""tara-doc: the specification's format table, opcode or encoding table and instruction sections,
in AsciiDoc, from the instruction metadata that the Sail plugin in tools/sail-doc reads from the
model."""

import itertools
import re
from dataclasses import dataclass
from enum import StrEnum, auto
from pathlib import Path
from typing import Self
from xml.etree import ElementTree as XML

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
from tara.doc_operation import Operation, Statement
from tara.doc_reference import PRIMITIVES, Context, Example, Helper, InstructionDoc

# A tint of the accent colour of styles.css and theme.yml; Asciidoctor takes only literal colours.
UNASSIGNED_BACKGROUND = "#F6DADF"
MNEMONIC = re.compile(r"[\w.]+")
FORMATS = "formats.adoc"
OPCODES = "opcodes.adoc"
INSTRUCTIONS = "instructions.adoc"
HELPERS = "helpers.adoc"
LEGACY_FORMAL = "formal.adoc"
NOTATION = "notation.adoc"
ENCODINGS = "encodings"

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
    execution: tuple[Statement, ...]
    documentation: InstructionDoc | None = None
    description: str = ""
    examples: tuple[Example, ...] = ()

    @property
    def operation(self) -> Operation:
        return Operation(statements=self.execution)

    def diagram(self, *, anchor: str, word_width: int) -> str:
        canvas = 960
        unit = canvas / word_width
        root = XML.Element(
            "svg",
            {
                "xmlns": "http://www.w3.org/2000/svg",
                "viewBox": "0 0 984 142",
                "role": "img",
                "aria-labelledby": f"{anchor}-title {anchor}-description",
            },
        )
        XML.SubElement(root, "title", {"id": f"{anchor}-title"}).text = (
            f"{self.mnemonic} instruction encoding"
        )
        description = XML.SubElement(root, "desc", {"id": f"{anchor}-description"})
        descriptions: list[str] = []
        start = word_width
        offset = 12.0
        for field in self.fields:
            high, low = start - 1, start - field.width
            width = field.width * unit
            label = field.label or "fixed"
            if isinstance(field, Ignored):
                label = "ignored"

            value = field.bits if isinstance(field, Fixed) else f"{field.width} bits"
            descriptions.append(f"bits {high}:{low}: {label}, {value}")
            XML.SubElement(
                root,
                "rect",
                {
                    "x": str(offset),
                    "y": "40",
                    "width": str(width),
                    "height": "66",
                    "fill": (
                        "#F7ECEE"
                        if isinstance(field, Fixed)
                        else "#F3F3F3" if isinstance(field, Ignored) else "#FFFCFC"
                    ),
                    "stroke": "#A3242F",
                    "stroke-width": "1",
                },
            )
            labels = [(offset + 5, 27, str(high), "start")]
            if high != low:
                labels.append((offset + width - 5, 27, str(low), "end"))

            center = offset + width / 2
            display = label if len(label) * 11 < width - 10 else f"f{len(descriptions)}"
            labels.extend(
                [
                    (center, 64, display, "middle"),
                    (center, 89, value if len(value) * 10 < width - 10 else "fixed", "middle"),
                ]
            )
            for x, y, text, alignment in labels:
                XML.SubElement(
                    root,
                    "text",
                    {
                        "x": str(x),
                        "y": str(y),
                        "text-anchor": alignment,
                        "font-family": "JetBrainsMono",
                        "font-size": "18",
                        "fill": "#202027",
                    },
                ).text = text

            offset += width
            start = low

        description.text = "; ".join(descriptions)
        return XML.tostring(root, encoding="unicode") + "\n"

    def section(
        self,
        *,
        anchor: str,
        format: Format,
        level: int,
        word_width: int,
        related: dict[str, str],
    ) -> str:
        title = self.documentation.title if self.documentation is not None else self.mnemonic
        lines = [
            f"[#{anchor}.instruction]",
            f"{'=' * level} `{self.mnemonic}` — {title}",
            "",
            "[.instruction-lead%unbreakable]",
            "--",
            "",
            f"*{Code(self.syntax)}*",
            "",
            f"{word_width}-bit instruction · {Link(target=format.anchor, content=Text(format.name))}",
            "",
            self.description,
            "",
            ".Encoding",
            f"image::{ENCODINGS}/{anchor}.svg[{self.mnemonic} encoding,opts=inline,pdfwidth=100%,role=encoding-diagram]",
            "",
            "--",
            "",
        ]
        if self.condition:
            lines += [f"Encoding constraint: {Code(self.condition)}.", ""]

        descriptions = (
            {operand.name: operand for operand in self.documentation.operands}
            if self.documentation is not None
            else {}
        )
        rows: list[Row] = []
        start = word_width
        for field in self.fields:
            high, low = start - 1, start - field.width
            bits = str(high) if high == low else f"{high}:{low}"
            if isinstance(field, Operand):
                doc = descriptions.get(field.name)
                meaning = doc.description if doc is not None else f"{field.width}-bit operand"
                rows.append(
                    Row(
                        cells=(
                            Cell(content=(Code(field.name),)),
                            Cell(content=(Code(bits),)),
                            Cell(content=(Text(meaning),)),
                        )
                    )
                )
            elif isinstance(field, Ignored):
                rows.append(
                    Row(
                        cells=(
                            Cell(content=(Text("ignored"),)),
                            Cell(content=(Code(bits),)),
                            Cell(
                                content=(Text("Encoder writes zeros; decoder accepts any value."),)
                            ),
                        )
                    )
                )

            start = low

        if rows:
            lines += [
                ".Operands and encoding fields",
                str(
                    Table(
                        columns=(Column(), Column(), Column(width=5)),
                        header=("Field", "Bits", "Meaning"),
                        rows=tuple(rows),
                    )
                ),
                "",
            ]

        rendered = self.operation.card
        lines += [".Operation", "[listing,role=operation]", "----", rendered, "----", ""]

        if self.documentation is not None:
            for note in self.documentation.notes:
                lines += [
                    f"*{note.category.title()}{' (model)' if note.category == 'assumption' else ''}:* {note.text}",
                    "",
                ]

            if self.documentation.related:
                lines += [
                    "Related: "
                    + " · ".join(
                        str(Link(target=related[name], content=Code(name)))
                        for name in self.documentation.related
                    )
                    + ".",
                    "",
                ]

        return "\n".join(lines)

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

    def cells(self, format: Format, anchor: str) -> tuple[Cell, ...]:
        execution: list[Inline] = []
        for statement in self.operation.card_lines:
            execution += [*([LineBreak()] if execution else []), Code(statement)]

        return (
            Cell(content=(Link(target=anchor, content=Code(self.syntax)),)),
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
    source: str = ""
    description: str = ""


class AnchorEntry(msgspec.Struct, frozen=True, tag="anchor", tag_field="kind"):
    name: str

    def section(self) -> str:
        return f"include::comments/anchor/{self.name}.adoc[]\n"


class ConstructorEntry(msgspec.Struct, frozen=True, tag="constructor", tag_field="kind"):
    """An instruction constructor and the clauses that take it apart, in source order."""

    name: str
    clauses: tuple[Clause, ...]


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


class Fragment(msgspec.Struct, frozen=True, kw_only=True):
    name: str
    description: str


class CommentKind(StrEnum):
    ANCHOR = auto()
    REGISTER = auto()
    LET = auto()


class Prose(msgspec.Struct, frozen=True, kw_only=True):
    anchors: tuple[Fragment, ...] = ()
    registers: tuple[Fragment, ...] = ()
    constants: tuple[Fragment, ...] = ()

    def write(self, directory: Path) -> None:
        for kind, fragments in (
            (CommentKind.ANCHOR, self.anchors),
            (CommentKind.REGISTER, self.registers),
            (CommentKind.LET, self.constants),
        ):
            destination = directory / "comments" / kind
            destination.mkdir(parents=True, exist_ok=True)
            for old in destination.glob("*.adoc"):
                old.unlink()

            for fragment in fragments:
                (destination / f"{fragment.name}.adoc").write_text(f"{fragment.description}\n")


class InstructionSet(msgspec.Struct, frozen=True, kw_only=True):
    """The instructions of an instruction set whose words are `word_width` bits, and the outline
    of the files that define them: their documented anchors and constructors, in source order."""

    word_width: int
    instructions: tuple[Instruction, ...]
    outline: tuple[AnchorEntry | ConstructorEntry, ...]
    schema_version: int = 3
    prose: Prose = Prose()
    helpers: tuple[Helper, ...] = ()
    retirement: tuple[Statement, ...] = ()
    complete: bool = False
    context: Context | None = None

    def __post_init__(self) -> None:
        if self.schema_version != 3:
            raise ValueError(f"unsupported documentation schema version {self.schema_version}")

        if self.word_width < 1 or not self.instructions:
            raise ValueError("documentation needs a positive word width and instructions")

        for instruction in self.instructions:
            if any(field.width < 1 for field in instruction.fields):
                raise ValueError(
                    f"{instruction.constructor}: encoding fields must have positive widths"
                )

            if any(
                isinstance(field, Fixed) and set(field.bits) - {"0", "1"}
                for field in instruction.fields
            ):
                raise ValueError(
                    f"{instruction.constructor}: fixed fields must contain binary digits"
                )

            if sum(field.width for field in instruction.fields) != self.word_width:
                raise ValueError(f"{instruction.constructor}: encoding fields do not fill the word")

        anchors = list(self.anchor_of.values())
        if len(anchors) != len(set(anchors)) or any(
            not re.fullmatch(r"[A-Za-z0-9_.-]+", anchor) for anchor in anchors
        ):
            raise ValueError(
                "instruction IDs must be unique and contain letters, digits, dots, underscores or hyphens"
            )

        if self.complete:
            known = self.helper_names
            references = Operation(statements=self.retirement).references
            for instruction in self.instructions:
                references |= instruction.operation.references
                if instruction.documentation is None or not instruction.description:
                    raise ValueError(f"{instruction.constructor}: incomplete documentation")

            for helper in self.helpers:
                references |= helper.references

            if missing := references - known:
                raise ValueError(f"undefined documentation helpers: {', '.join(sorted(missing))}")

        helper_names = [helper.name for helper in self.helpers]
        if len(helper_names) != len(set(helper_names)) or set(helper_names) & {
            primitive.name for primitive in PRIMITIVES
        }:
            raise ValueError("model helper names must be unique and distinct from primitive names")

        related = self.related_targets
        for instruction in self.instructions:
            if instruction.documentation is not None:
                for name in instruction.documentation.related:
                    if name not in related:
                        raise ValueError(
                            f"{instruction.mnemonic}: unknown or ambiguous related instruction {name}"
                        )

    @property
    def helper_names(self) -> set[str]:
        return {helper.name for helper in self.helpers} | {
            primitive.name for primitive in PRIMITIVES
        }

    @property
    def anchor_of(self) -> dict[Instruction, str]:
        counts = {
            name: sum(instruction.constructor == name for instruction in self.instructions)
            for name in {instruction.constructor for instruction in self.instructions}
        }
        return {
            instruction: (
                section_anchor(instruction.documentation.id)
                if instruction.documentation is not None
                and instruction.documentation.id is not None
                else section_anchor(instruction.constructor)
                + (f"-{instruction.mnemonic}" if counts[instruction.constructor] > 1 else "")
            )
            for instruction in self.instructions
        }

    @property
    def related_targets(self) -> dict[str, str]:
        anchors = self.anchor_of
        return {
            instruction.mnemonic: anchors[instruction]
            for instruction in self.instructions
            if sum(other.mnemonic == instruction.mnemonic for other in self.instructions) == 1
        }

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
                            *by_opcode[opcode].cells(
                                format_of[by_opcode[opcode]], self.anchor_of[by_opcode[opcode]]
                            ),
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
                Column(alignment=Alignment.CENTER),
                Column(),
                Column(),
                Column(alignment=Alignment.CENTER),
            ),
            header=("Opcode", "Syntax", "Execution", "Format"),
            rows=tuple(rows),
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
                    *instruction.cells(format_of[instruction], self.anchor_of[instruction]),
                )
            )
            for instruction in self.by_encoding
        )
        return Table(
            columns=(
                Column(alignment=Alignment.CENTER),
                *([Column()] if guarded else []),
                Column(),
                Column(),
                Column(alignment=Alignment.CENTER),
            ),
            header=(
                "Encoding",
                *(["Condition"] if guarded else []),
                "Syntax",
                "Execution",
                "Format",
            ),
            rows=rows,
        )

    def sections(self, *, level: int) -> str:
        """The outline: each documented anchor of the files that define instructions, and each
        constructor's section at heading `level`, in source order."""

        sections: list[str] = []
        anchors = self.anchor_of
        formats = self.format_of()
        for entry in self.outline:
            if isinstance(entry, AnchorEntry):
                sections.append(entry.section())
                continue

            variants = [
                instruction
                for instruction in self.instructions
                if instruction.constructor == entry.name
            ]
            if len(variants) > 1:
                sections.append(
                    f"[#{section_anchor(entry.name)}]\n{'=' * level} `{entry.name}` variants\n"
                )

            sections.extend(
                instruction.section(
                    anchor=anchors[instruction],
                    format=formats[instruction],
                    level=level + (len(variants) > 1),
                    word_width=self.word_width,
                    related=self.related_targets,
                )
                for instruction in variants
            )

        return "\n".join(sections)

    def helper_sections(self) -> str:
        sections = ["[appendix]\n[#helpers]\n== Helper definitions\n"]
        sections.extend(primitive.section() for primitive in PRIMITIVES)
        for helper in self.helpers:
            sections += [
                f"[#{helper.anchor}]\n=== `{helper.name}` — {helper.title}\n",
                str(Code(helper.signature)),
                "",
            ]
            if helper.description:
                sections.append(helper.description)

            if helper.operation:
                sections += [
                    ".Definition",
                    "[listing,role=operation]",
                    "----",
                    Operation(statements=helper.operation).card,
                    "----",
                    "",
                ]

            if helper.rules:
                sections += [
                    ".Mapping rules",
                    "[listing,role=operation]",
                    "----",
                    *(rule.line() for rule in helper.rules),
                    "----",
                    "",
                ]

        return "\n".join(sections)

    def notation_section(self) -> str:
        lines = [
            "[#notation]\n=== Reading the instruction reference\n",
            "Bit 0 is least significant; `x[high:low]` includes both endpoints. The model's notation names architectural registers and accessors.\n",
            "A bit vector has a fixed width. Arithmetic wraps at that width and treats values as unsigned unless `s(x)` is written. `sextN(x)` and `zextN(x)` extend to N bits; `++` concatenates bits. Signed interpretation returns an integer; sign extension returns a wider bit vector.\n",
            "Operations run from top to bottom. A local binding saves its value at that point; a later register read sees any earlier write. Logical shifts fill with zeros.\n",
            "The <<helpers,helper appendix>> defines the functions used in these operations.\n",
        ]
        if self.retirement:
            lines += [
                "[#instruction-retirement]\n==== Instruction retirement\n",
                "PC holds the current instruction's address. `PC_next` is temporary execution state. When the halt latch is clear, the driver latches input lines and performs this shared sequence:\n",
                "[listing,role=operation]\n----",
                Operation(statements=self.retirement).card,
                "----\n",
                "Each instruction's Operation block supplies `execute(insn)` in this sequence; the surrounding steps apply to every instruction. HLT completes this sequence; subsequent calls report Stopped.\n",
            ]

        return "\n".join(lines)


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

    try:
        instruction_set = InstructionSet.read(metadata)
    except (msgspec.DecodeError, ValueError) as error:
        raise click.ClickException(f"{metadata}: {error}") from error
    directory.mkdir(parents=True, exist_ok=True)
    instruction_set.prose.write(directory)
    (directory / FORMATS).write_text(str(instruction_set.format_table()))
    (directory / OPCODES).write_text(str(instruction_set.opcodes()))
    (directory / INSTRUCTIONS).write_text(instruction_set.sections(level=section_level))
    (directory / HELPERS).write_text(instruction_set.helper_sections())
    (directory / LEGACY_FORMAL).unlink(missing_ok=True)
    (directory / NOTATION).write_text(instruction_set.notation_section())
    diagrams = directory / ENCODINGS
    diagrams.mkdir(exist_ok=True)
    for old in diagrams.glob("insn-*.svg"):
        old.unlink()

    for instruction, anchor in instruction_set.anchor_of.items():
        (diagrams / f"{anchor}.svg").write_text(
            instruction.diagram(anchor=anchor, word_width=instruction_set.word_width)
        )


if __name__ == "__main__":
    main(prog_name="tara-doc")
