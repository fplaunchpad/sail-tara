"""The specification as LaTeX: the sections of a document, for `\\input` into a frame.

The listings are Sail's own: the macros of the `commands.tex` that `sail --latex` writes, which
typeset a definition with hyperlinks from its calls to their definitions. The frame (`doc/tara.tex`)
styles the document and defines what the sections use besides:

    \\code{TEXT}                   program text
    \\xref{LABEL}{TEXT}            a link to a label, which must exist
    \\keep{LISTINGS}               listings that stay together, with the paragraph before them
    \\anchoronly{MACRO}            the label of a Sail macro, without its listing
    \\group{TITLE}{LABEL}          a subsection of instructions
    \\begin{instruction}{LABEL}{MNEMONIC}{FACTS}{DESCRIPTION} ... \\end{instruction}
    \\fact{NAME}{VALUE}            one of the FACTS of an instruction
    \\begin{display} ... \\end{display}   a centred table, with the paragraph before it
    \\fld{N}{TEXT}, \\fldlast{N}{TEXT}, \\bitnumber{N}   the fields of a format diagram
"""

from dataclasses import dataclass

import click

from tara.document import (
    Block,
    Category,
    Definition,
    Described,
    FormatField,
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
from tara.sail_doc import Macros

ESCAPES = {
    "\\": r"\textbackslash{}",
    "{": r"\{",
    "}": r"\}",
    "$": r"\$",
    "&": r"\&",
    "#": r"\#",
    "^": r"\textasciicircum{}",
    "_": r"\_",
    "%": r"\%",
    "~": r"\textasciitilde{}",
    # Without the braces, two of them next to each other are a ligature.
    "<": r"\textless{}",
    ">": r"\textgreater{}",
}
OPENING_QUOTE = r"\textquotedblleft{}"
CLOSING_QUOTE = r"\textquotedblright{}"
MINUS = "$-$"
# What a quotation mark follows if it opens a quotation.
OPENS_AFTER = (" ", "(")

# The names of Sail's tables of macros, by the kind of definition.
SAIL_CATEGORY = {
    Category.TYPE: "type",
    Category.REGISTER: "register",
    Category.LET: "let",
    Category.VAL: "val",
    Category.FUNCTION: "fn",
}


@dataclass(eq=False)
class ListingMismatch(click.ClickException):
    """The listing that Sail's LaTeX macro typesets is not the source of the definition."""

    macro: str
    listing: str
    source: str

    def __post_init__(self) -> None:
        super().__init__(
            f"Sail's listing \\{self.macro} is not the source of its definition:\n"
            f"{self.listing}\nis not\n{self.source}"
        )


def escape(text: str) -> str:
    """`text` as LaTeX that prints it, in a typewriter font as well as in a text font."""

    return "".join(ESCAPES.get(character, character) for character in text)


def code(text: str) -> str:
    return rf"\code{{{escape(text)}}}"


def typeset_words(text: str, *, first: bool) -> str:
    """`text` as LaTeX for a text font: quotation marks are curly, and the minus sign of a number is
    long. `first` tells that the text starts its paragraph."""

    typeset = list[str]()
    for index, character in enumerate(text):
        before = text[index - 1] if index else None
        after = text[index + 1] if index + 1 < len(text) else ""
        starts_number = after.isdigit() and not (before or " ").isalnum() and before != "-"
        if character == '"':
            opens = (before is None and first) or before in OPENS_AFTER
            typeset.append(OPENING_QUOTE if opens else CLOSING_QUOTE)
        elif character == "-" and starts_number:
            typeset.append(MINUS)
        else:
            typeset.append(escape(character))

    return "".join(typeset)


def normalized(text: str) -> str:
    """`text` without its spaces and breaks, which a listing may lay out differently."""

    return "".join(text.split())


def field_cell(field: FormatField, *, last: bool) -> str:
    """A cell of a format diagram: the box of the field, which closes on the right if it is the last
    of its row."""

    command = "fldlast" if last else "fld"
    label = code(field.label) if field.code else field.label
    return rf"\{command}{{{field.width}}}{{{label}}}"


@dataclass(frozen=True, kw_only=True)
class Renderer:
    """Renders a specification with the macros of Sail's LaTeX output for its model."""

    specification: Specification
    macros: Macros

    def spans(self, spans: Spans, *, own: str | None) -> str:
        """The spans of a paragraph. Code that names a definition links to it, unless it is in the
        description of that definition, whose anchor is `own`."""

        parts = list[str]()
        for index, span in enumerate(spans):
            match span:
                case Words(text=text):
                    parts.append(typeset_words(text, first=index == 0))
                case Code(text=text):
                    anchor = self.specification.symbols.get(text)
                    link = anchor not in (None, own)
                    parts.append(rf"\xref{{{anchor}}}{{{code(text)}}}" if link else code(text))

        return "".join(parts)

    def prose(self, prose: Prose, *, own: str | None = None) -> str:
        blocks = list[str]()
        for block in prose.blocks:
            match block:
                case Paragraph(spans=spans):
                    blocks.append(self.spans(spans, own=own))
                case Bullets(items=items):
                    lines = [rf"\item {self.spans(item, own=own)}" for item in items]
                    blocks.append("\n".join([r"\begin{itemize}", *lines, r"\end{itemize}"]))

        return "\n\n".join(blocks)

    def check(self, definition: Definition, macro: str) -> None:
        """Check that `macro` typesets the source of `definition`. Sail prints a val without its
        keyword."""

        if definition.source is None:
            return

        expected = definition.source
        if definition.category is Category.VAL:
            expected = expected.removeprefix("val ")

        listing = self.macros.listing_text(macro)
        if normalized(listing) != normalized(expected):
            raise ListingMismatch(macro, listing, expected)

    def macro(self, definition: Definition) -> str:
        """The LaTeX that typesets `definition`."""

        if definition.category is Category.CLAUSE:
            macro = self.macros.clause_macro(definition.name, definition.number)
        else:
            category = SAIL_CATEGORY[definition.category]
            macro = self.macros.named_macro(category, definition.name)

        self.check(definition, macro)
        # A function that has its signature inline shows it in its own listing: its val is only
        # a target for the links of the other listings.
        return rf"\anchoronly{{\{macro}}}" if definition.source is None else rf"\{macro}"

    def listing(self, listing: Listing) -> str:
        label = "" if listing.anchor is None else rf"\phantomsection\label{{{listing.anchor}}}"
        return "\\keep{" + label + "\n".join(self.macro(d) for d in listing.definitions) + "}"

    def instruction(self, instruction: Instruction) -> str:
        facts = (
            rf"\fact{{Syntax}}{{{code(instruction.syntax)}}}"
            rf"\fact{{Opcode}}{{{instruction.opcode} ({code(instruction.bits)})}}"
            rf"\fact{{Format}}{{\xref{{{instruction.format_anchor}}}{{{instruction.format}}}}}"
        )
        description = self.prose(instruction.description, own=instruction.anchor)
        return "\n".join(
            [
                rf"\begin{{instruction}}{{{instruction.anchor}}}{{{escape(instruction.mnemonic)}}}"
                rf"{{{facts}}}{{{description}}}",
                *(self.macro(d) for d in instruction.listing.definitions),
                r"\end{instruction}",
            ]
        )

    def format_diagram(self, table: FormatTable) -> str:
        bits = table.formats[0].width
        numbers = " & ".join(rf"\bitnumber{{{n}}}" for n in range(bits - 1, -1, -1))
        columns = rf"*{{{bits}}}{{@{{}}>{{\centering\arraybackslash}}p{{\bitwidth}}@{{}}}}"
        line = rf"\cline{{2-{bits + 1}}}"
        rows = [
            r"\begin{display}",
            r"\renewcommand{\arraystretch}{1.25}",
            rf"\begin{{tabular}}{{@{{}}l@{{\hspace{{6pt}}}}{columns}>{{\hspace{{10pt}}}}l@{{}}}}",
            rf" & {numbers} & \\",
            line,
        ]
        for layout in table.formats:
            last = len(layout.fields) - 1
            cells = [field_cell(field, last=n == last) for n, field in enumerate(layout.fields)]
            label = rf"\phantomsection\label{{{layout.anchor}}}{layout.name}"
            mnemonics = rf"\small {', '.join(layout.mnemonics)}"
            rows.append(rf"{label} & {' & '.join(cells)} & {mnemonics} \\ {line}")

        return "\n".join([*rows, r"\end{tabular}", r"\end{display}"])

    def opcode_table(self, table: OpcodeTable) -> str:
        digits = (table.width + 3) // 4

        def hexadecimal(value: int) -> str:
            return rf"\code{{{value:0{digits}X}}}"

        def binary(value: int) -> str:
            return rf"\code{{{value:0{table.width}b}}}"

        rows = [
            r"\begin{display}",
            r"\small",
            r"\begin{tabular}{@{}rcc@{\hspace{1.2em}}l@{\hspace{1.2em}}l@{\hspace{1.2em}}cr@{}}",
            r"\toprule",
            r"Opcode & Hex & Bits & Mnemonic & Syntax & Format & Page \\",
            r"\midrule",
        ]
        for row in table.rows:
            match row:
                case OpcodeRow():
                    mnemonic = rf"\xref{{{row.anchor}}}{{{code(row.mnemonic)}}}"
                    layout = rf"\xref{{{row.format_anchor}}}{{{row.format}}}"
                    rows.append(
                        rf"{row.opcode} & {hexadecimal(row.opcode)} & {binary(row.opcode)} & "
                        rf"{mnemonic} & {code(row.syntax)} & {layout} & \pageref{{{row.anchor}}} \\"
                    )
                case OpcodeGap():
                    rows.append(
                        rf"{row.first}--{row.last} & "
                        rf"{hexadecimal(row.first)}--{hexadecimal(row.last)} & "
                        rf"{binary(row.first)}--{binary(row.last)} & "
                        r"\multicolumn{4}{l}{unassigned} \\"
                    )

        return "\n".join([*rows, r"\bottomrule", r"\end{tabular}", r"\end{display}"])

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
        title = escape(section.title)
        if level == 1:
            heading = rf"\section{{{title}}}\label{{{section.anchor}}}"
        else:
            heading = rf"\group{{{title}}}{{{section.anchor}}}"

        parts = [heading, *(self.block(block) for block in section.blocks)]
        parts.extend(self.section(child, level=level + 1) for child in section.sections)
        return "\n\n".join(parts)


def render_latex(specification: Specification, macros: Macros) -> str:
    """The sections of `specification` in LaTeX, for the frame in `doc/tara.tex` to `\\input`."""

    renderer = Renderer(specification=specification, macros=macros)
    parts = [
        "% Generated by tara.specification from the Sail model: do not edit.",
        renderer.prose(specification.introduction),
        *(renderer.section(section, level=1) for section in specification.sections),
    ]
    return "\n\n".join(parts) + "\n"
