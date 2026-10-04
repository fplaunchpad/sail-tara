"""The specification as AsciiDoc: a document that `asciidoctor` renders as HTML.

The listings are the source text of the definitions, as `[source,sail]` blocks. The text of the
model's comments is escaped for AsciiDoc, so that no character of it starts markup.
"""

import re
from dataclasses import dataclass

from tara.document import (
    SUBTITLE,
    TITLE,
    Block,
    Category,
    Described,
    FormatTable,
    Instruction,
    Listing,
    OpcodeGap,
    OpcodeRow,
    OpcodeTable,
    Section,
    Specification,
)
from tara.prose import Bullets, Code, Paragraph, Prose, Spans, Words

HEADER = f"""= {TITLE}
:toc: left
:toclevels: 3
:sectnums:
:reproducible:
:nofooter:

[.lead]
{SUBTITLE}."""

# Text of these characters, and no other, has no meaning in AsciiDoc. Where it has more, a
# replacement such as (C) or --, it is passed through as it is.
PLAIN = re.compile(r"[A-Za-z0-9 .,;:'\"()/=?!-]*")
REPLACED = ("(C)", "(R)", "(TM)", "--", "...", "->", "<-", "=>", "<=")
NO_BREAK_SPACES = "{nbsp}{nbsp}{nbsp}"
MONOSPACE_CELL = "^m"


def passed(text: str) -> str:
    """`text` as an inline passthrough: nothing in it is interpreted but the special characters."""

    return "pass:c[" + text.replace("]", r"\]") + "]"


def plain(text: str) -> str:
    """`text` as AsciiDoc that prints it."""

    if PLAIN.fullmatch(text) and not any(replaced in text for replaced in REPLACED):
        return text

    return passed(text)


def code(text: str) -> str:
    """`text` as AsciiDoc for program text: monospace, with nothing in it interpreted."""

    if text.endswith("+") or "+`" in text:
        return f"`{passed(text)}`"

    return f"`+{text}+`"


@dataclass(frozen=True, kw_only=True)
class Renderer:
    specification: Specification

    def spans(self, spans: Spans, *, own: str | None) -> str:
        """The spans of a paragraph. Code that names a definition links to it, unless it is in the
        description of that definition, whose anchor is `own`."""

        parts = list[str]()
        for span in spans:
            match span:
                case Words(text=text):
                    parts.append(plain(text))
                case Code(text=text):
                    anchor = self.specification.symbols.get(text)
                    link = anchor not in (None, own)
                    parts.append(f"<<{anchor},{code(text)}>>" if link else code(text))

        return "".join(parts)

    def prose(self, prose: Prose, *, own: str | None = None) -> str:
        blocks = list[str]()
        for block in prose.blocks:
            match block:
                case Paragraph(spans=spans):
                    blocks.append(self.spans(spans, own=own))
                case Bullets(items=items):
                    blocks.append("\n".join(f"* {self.spans(item, own=own)}" for item in items))

        return "\n\n".join(blocks)

    def listing(self, listing: Listing) -> str:
        """A block of the source of the definitions that have source text of their own. A val is
        set off from the function after it, as in the model."""

        source = ""
        previous: Category | None = None
        for definition in listing.definitions:
            if definition.source is not None:
                if source:
                    source += "\n\n" if previous is Category.VAL else "\n"

                source += definition.source
                previous = definition.category

        anchor = "" if listing.anchor is None else f"[#{listing.anchor}]\n"
        return f"{anchor}[source,sail]\n----\n{source}\n----"

    def instruction(self, instruction: Instruction) -> str:
        facts = NO_BREAK_SPACES.join(
            [
                f"**Syntax** {code(instruction.syntax)}",
                f"**Opcode** {instruction.opcode} ({code(instruction.bits)})",
                f"**Format** <<{instruction.format_anchor},{instruction.format}>>",
            ]
        )
        return "\n\n".join(
            [
                f"[#{instruction.anchor}]\n==== {instruction.mnemonic}",
                facts,
                self.prose(instruction.description, own=instruction.anchor),
                self.listing(instruction.listing),
            ]
        )

    def format_diagram(self, table: FormatTable) -> str:
        bits = table.formats[0].width
        numbers = " ".join(f"|{n}" for n in range(bits - 1, -1, -1))
        rows = [
            f'[cols="<1,{bits}*^1,<5", options="header"]',
            "|===",
            f"|Format {numbers} |Instructions",
            "",
        ]
        for layout in table.formats:
            cells = " ".join(
                f"{field.width}+{MONOSPACE_CELL}|{field.label}" for field in layout.fields
            )
            # The last cell is aligned by its own spec: it does not get its column's after a span.
            mnemonics = ", ".join(layout.mnemonics)
            rows.append(f"|[[{layout.anchor}]]{layout.name} {cells} <|{mnemonics}")

        return "\n".join([*rows, "|==="])

    def opcode_table(self, table: OpcodeTable) -> str:
        digits = (table.width + 3) // 4

        def hexadecimal(value: int) -> str:
            return code(f"{value:0{digits}X}")

        def binary(value: int) -> str:
            return code(f"{value:0{table.width}b}")

        rows = [
            '[cols="^1,^1,^2,2,4,^1", options="header"]',
            "|===",
            "|Opcode |Hex |Bits |Mnemonic |Syntax |Format",
            "",
        ]
        for row in table.rows:
            match row:
                case OpcodeRow():
                    rows.append(
                        f"|{row.opcode} |{hexadecimal(row.opcode)} |{binary(row.opcode)} "
                        f"|<<{row.anchor},{code(row.mnemonic)}>> |{code(row.syntax)} "
                        f"|<<{row.format_anchor},{row.format}>>"
                    )
                case OpcodeGap():
                    rows.append(
                        f"|{row.first}-{row.last} "
                        f"|{hexadecimal(row.first)}-{hexadecimal(row.last)} "
                        f"|{binary(row.first)}-{binary(row.last)} 3+|unassigned"
                    )

        return "\n".join([*rows, "|==="])

    def block(self, block: Block) -> str:
        match block:
            case Prose():
                return self.prose(block)
            case Listing():
                return self.listing(block)
            case Described(prose=prose, listing=listing):
                return self.prose(prose, own=listing.anchor) + "\n\n" + self.listing(listing)
            case Instruction():
                return self.instruction(block)
            case FormatTable():
                return self.format_diagram(block)
            case OpcodeTable():
                return self.opcode_table(block)

    def section(self, section: Section, *, level: int) -> str:
        heading = f"[#{section.anchor}]\n{'=' * (level + 1)} {plain(section.title)}"
        parts = [heading, *(self.block(block) for block in section.blocks)]
        parts.extend(self.section(child, level=level + 1) for child in section.sections)
        return "\n\n".join(parts)


def render_asciidoc(specification: Specification) -> str:
    """`specification` as an AsciiDoc document."""

    renderer = Renderer(specification=specification)
    parts = [
        HEADER,
        renderer.prose(specification.introduction),
        *(renderer.section(section, level=1) for section in specification.sections),
    ]
    return "\n\n".join(parts) + "\n"
