"""The specification of TARA as a document, built from the documentation bundle of the Sail model.

What the document says comes from the model: its sections follow the model's files; its prose is
the documentation comments (`/*! ... */`) of the definitions and of the `$anchor` pragmas, which
hold prose of their own; its listings are the definitions; and the opcode table, the formats and
the syntax of each instruction are read from the instruction's clauses of `decode` and `assembly`.
The renderers (`tara.latex`, `tara.asciidoc`) turn the one `Specification` that `build` returns into
a document each, so that the two have the same content.
"""

import re
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

import click

from tara.instructions import (
    FORMATS,
    Encoding,
    Role,
    alias_widths,
    decoded_mnemonic,
    format_name,
    parse_encoding,
    parse_syntax,
)
from tara.prose import Prose, parse_prose
from tara.sail_doc import App, Bundle, Clause, Function, Source, Val

TITLE = "The TARA Instruction Set Architecture"
SUBTITLE = "Reference specification, typeset from the Sail model"
INTRODUCTION = (
    "This specification is typeset from the Sail model of TARA, in `model/`. Each listing is a "
    "definition of the model as it is written there, and the text around it is the definition's "
    "documentation comment. The listings are the normative text: where text and listing "
    "disagree, the listing is right."
)

# The files of the model that have a section each, in the order of the document. The instructions
# are in the files of a directory, one group of instructions to a file: the section of the file
# below has a subsection for the formats, one for the opcodes and one for each group.
SECTION_FILES = {
    "machine.sail": "Machine state",
    "tara.sail": "The instruction set",
    "step.sail": "Execution",
    "syntax.sail": "Assembly syntax",
}
INSTRUCTION_SET = "tara.sail"
GROUP_DIRECTORY = "instructions"

# What the model defines for each instruction, in the order of the listings of its entry. An
# instruction is a clause of the function that defines it, `execute`.
InstructionFunction = StrEnum("InstructionFunction", "ASSEMBLY ENCODE DECODE EXECUTE")
DEFINING = InstructionFunction.EXECUTE

# What a definition is. The documentation of a type is not in the bundle, so a type has none.
Category = StrEnum("Category", "TYPE REGISTER LET VAL FUNCTION CLAUSE")
SCATTERED_TYPE = "scattered"


def definition_anchor(name: str) -> str:
    return f"def-{name}"


def instruction_anchor(mnemonic: str) -> str:
    return f"insn-{mnemonic}"


def format_anchor(name: str) -> str:
    return f"fmt-{name}"


@dataclass(eq=False)
class SpecificationError(click.ClickException):
    """The model is not laid out the way the specification needs."""

    where: str
    problem: str

    def __post_init__(self) -> None:
        super().__init__(f"{self.where}: {self.problem}")


def place(source: Source) -> str:
    return f"{source.file}:{source.line}"


@dataclass(frozen=True, kw_only=True)
class Definition:
    """A definition of the model, shown as a listing: by Sail's LaTeX macro in LaTeX, and as source
    text in AsciiDoc. `number` is the place of a clause among those of the function `name`.
    `source` is None for the `val` of a function that gives its signature inline."""

    category: Category
    name: str
    number: int = 0
    source: str | None


@dataclass(frozen=True, kw_only=True)
class Listing:
    """Definitions shown together."""

    definitions: tuple[Definition, ...]

    @property
    def names(self) -> tuple[str, ...]:
        """The names that the definitions give, which the prose refers to; clauses have none."""

        named = (d.name for d in self.definitions if d.category is not Category.CLAUSE)
        return tuple(dict.fromkeys(named))

    @property
    def anchor(self) -> str | None:
        """What a reference to one of the names goes to."""

        return definition_anchor(self.names[0]) if self.names else None


@dataclass(frozen=True, kw_only=True)
class Described:
    """A definition with its documentation comment."""

    prose: Prose
    listing: Listing


@dataclass(frozen=True, kw_only=True)
class Instruction:
    """An instruction: its facts, its description and its clauses."""

    mnemonic: str
    opcode: int
    bits: str
    syntax: str
    format: str
    description: Prose
    listing: Listing

    @property
    def anchor(self) -> str:
        return instruction_anchor(self.mnemonic)

    @property
    def format_anchor(self) -> str:
        return format_anchor(self.format)


@dataclass(frozen=True, kw_only=True)
class FormatField:
    """A field of a format. `label` names it, as in `rd, rs`, or is the zeros of padding; `code` is
    False for the opcode, whose label is a word and not a name in the model."""

    label: str
    width: int
    code: bool


@dataclass(frozen=True, kw_only=True)
class Format:
    """A format: the fields of an instruction word, from the opcode on, and its instructions."""

    name: str
    fields: tuple[FormatField, ...]
    mnemonics: tuple[str, ...]

    @property
    def anchor(self) -> str:
        return format_anchor(self.name)

    @property
    def width(self) -> int:
        return sum(field.width for field in self.fields)


@dataclass(frozen=True, kw_only=True)
class FormatTable:
    formats: tuple[Format, ...]


@dataclass(frozen=True, kw_only=True)
class OpcodeRow:
    """An assigned opcode."""

    opcode: int
    mnemonic: str
    syntax: str
    format: str

    @property
    def anchor(self) -> str:
        return instruction_anchor(self.mnemonic)

    @property
    def format_anchor(self) -> str:
        return format_anchor(self.format)


@dataclass(frozen=True, kw_only=True)
class OpcodeGap:
    """Opcodes, `first` to `last`, that no instruction has."""

    first: int
    last: int


@dataclass(frozen=True, kw_only=True)
class OpcodeTable:
    """The opcodes in order, assigned or not; an opcode is `width` bits wide."""

    width: int
    rows: tuple[OpcodeRow | OpcodeGap, ...]


type Block = Prose | Listing | Described | Instruction | FormatTable | OpcodeTable


@dataclass(frozen=True, kw_only=True)
class Section:
    title: str
    blocks: tuple[Block, ...]
    sections: tuple[Section, ...] = ()

    @property
    def anchor(self) -> str:
        return "sec-" + re.sub(r"[^a-z0-9]+", "-", self.title.lower()).strip("-")


@dataclass(frozen=True, kw_only=True)
class Specification:
    introduction: Prose
    sections: tuple[Section, ...]
    # The anchor that each name refers to: the names of the definitions and the mnemonics.
    symbols: Mapping[str, str]


@dataclass(frozen=True, kw_only=True)
class Item:
    """A piece of a file that the document shows: a definition, or prose that has none. `source` is
    where it starts."""

    source: Source
    comment: str | None
    definitions: tuple[Definition, ...]


@dataclass(frozen=True, kw_only=True)
class InstructionClauses:
    """The clauses that define an instruction, one of each function of the model."""

    mnemonic: str
    clauses: Mapping[InstructionFunction, Clause]


@dataclass(frozen=True, kw_only=True)
class InstructionFacts:
    """An instruction with what the tables need of it, and where its `decode` clause is."""

    instruction: Instruction
    encoding: Encoding
    source: Source


def constructor(function: InstructionFunction, clause: Clause) -> str | None:
    """The instruction that `clause` of `function` is for, if it is for one. A clause of `decode`
    returns the instruction; the clauses of the other functions match it."""

    if function is InstructionFunction.DECODE:
        return decoded_mnemonic(clause)

    return clause.pattern.name if isinstance(clause.pattern, App) else None


def find_instructions(bundle: Bundle) -> list[InstructionClauses]:
    """The instructions, in the order of the clauses of `execute`, each with the clauses of the
    other functions that are for it."""

    by_function = dict[InstructionFunction, dict[str, Clause]]()
    for function in InstructionFunction:
        found = dict[str, Clause]()
        scattered = bundle.functions.get(function)
        for clause in () if scattered is None else scattered.clauses:
            if (mnemonic := constructor(function, clause)) is not None:
                if mnemonic in found:
                    raise SpecificationError(
                        place(clause.source), f"{function} has two clauses for {mnemonic}"
                    )

                found[mnemonic] = clause

        by_function[function] = found

    for function, found in by_function.items():
        for mnemonic, clause in found.items():
            if mnemonic not in by_function[DEFINING]:
                raise SpecificationError(
                    place(clause.source),
                    f"{function} has a clause for {mnemonic}, {DEFINING} has none",
                )

    instructions = list[InstructionClauses]()
    for mnemonic, defining in by_function[DEFINING].items():
        clauses = dict[InstructionFunction, Clause]()
        for function in InstructionFunction:
            if mnemonic not in by_function[function]:
                raise SpecificationError(
                    place(defining.source), f"{mnemonic} has no clause of {function}"
                )

            clauses[function] = by_function[function][mnemonic]

        instructions.append(InstructionClauses(mnemonic=mnemonic, clauses=clauses))

    return instructions


def consumed_clauses(instructions: Iterable[InstructionClauses]) -> dict[str, set[int]]:
    """The numbers of the clauses of each function that the instructions show."""

    consumed = dict[str, set[int]]()
    for instruction in instructions:
        for function, clause in instruction.clauses.items():
            consumed.setdefault(str(function), set()).add(clause.number)

    return consumed


def require_comment(comment: str | None, *, name: str, source: Source) -> str:
    if comment is None:
        raise SpecificationError(place(source), f"{name} has no documentation comment")

    return comment


def definition(category: Category, name: str, source: Source | None) -> Definition:
    return Definition(category=category, name=name, source=None if source is None else source.text)


def clause_definition(function: str, clause: Clause) -> Definition:
    return Definition(
        category=Category.CLAUSE,
        name=str(function),
        number=clause.number,
        source=clause.source.text,
    )


def function_items(
    *, name: str, val: Val | None, function: Function | None, consumed: set[int]
) -> Iterable[Item]:
    """The items of the function `name` and of its val. A function of one clause is shown whole,
    with its val; of a scattered function the val is shown, and the clauses that no instruction
    uses one by one."""

    if function is not None and len(function.clauses) == 1:
        clause = function.clauses[0]
        if val is None:
            first, comment = clause.source, clause.comment
        elif val.comment is not None and clause.comment is not None:
            raise SpecificationError(place(clause.source), f"{name} has two documentation comments")
        else:
            first, comment = val.source, val.comment or clause.comment

        yield Item(
            source=first,
            comment=require_comment(comment, name=name, source=first),
            definitions=(
                definition(Category.VAL, name, None if val is None else val.source),
                definition(Category.FUNCTION, name, clause.source),
            ),
        )
        return

    if val is not None:
        yield Item(
            source=val.source,
            comment=require_comment(val.comment, name=name, source=val.source),
            definitions=(definition(Category.VAL, name, val.source),),
        )

    for clause in () if function is None else function.clauses:
        if clause.number not in consumed:
            yield Item(
                source=clause.source,
                comment=require_comment(clause.comment, name=name, source=clause.source),
                definitions=(clause_definition(name, clause),),
            )


def collect_items(bundle: Bundle, consumed: Mapping[str, set[int]]) -> dict[Path, list[Item]]:
    """The items of each file of the model: its anchors and its definitions, except for the clauses
    of `consumed`, which instructions show."""

    items = list[Item]()
    for anchor in bundle.anchors.values():
        comment = require_comment(
            anchor.comment, name=f"anchor {anchor.name}", source=anchor.source
        )
        items.append(Item(source=anchor.source, comment=comment, definitions=()))

    for type_definition in bundle.types.values():
        # A scattered type is declared where it starts; the instructions declare its constructors.
        source = type_definition.source
        if not source.text.startswith(SCATTERED_TYPE):
            definitions = (definition(Category.TYPE, type_definition.name, source),)
            items.append(Item(source=source, comment=None, definitions=definitions))

    for register in bundle.registers.values():
        comment = require_comment(register.comment, name=register.name, source=register.source)
        definitions = (definition(Category.REGISTER, register.name, register.source),)
        items.append(Item(source=register.source, comment=comment, definitions=definitions))

    for let in bundle.lets.values():
        comment = require_comment(let.comment, name=let.name, source=let.source)
        definitions = (definition(Category.LET, let.name, let.source),)
        items.append(Item(source=let.source, comment=comment, definitions=definitions))

    for name in sorted(bundle.vals.keys() | bundle.functions.keys()):
        items.extend(
            function_items(
                name=name,
                val=bundle.vals.get(name),
                function=bundle.functions.get(name),
                consumed=consumed.get(name, set()),
            )
        )

    by_file = dict[Path, list[Item]]()
    for item in items:
        by_file.setdefault(item.source.file, []).append(item)

    return by_file


def blocks_of(items: Iterable[Item]) -> tuple[Block, ...]:
    """The blocks that show `items`, in their order in the file. A definition without a comment,
    which only a type is, joins the listing before it."""

    blocks = list[Block]()
    for item in sorted(items, key=lambda item: item.source.position):
        listing = Listing(definitions=item.definitions)
        if item.comment is not None:
            prose = parse_prose(item.comment, where=place(item.source))
            blocks.append(Described(prose=prose, listing=listing) if listing.definitions else prose)
        elif blocks and isinstance(blocks[-1], Listing):
            blocks[-1] = Listing(definitions=blocks[-1].definitions + listing.definitions)
        else:
            blocks.append(listing)

    return tuple(blocks)


def read_instruction(clauses: InstructionClauses, widths: Mapping[str, int]) -> InstructionFacts:
    """The instruction that `clauses` define, with its facts read from them."""

    mnemonic = clauses.mnemonic
    defining = clauses.clauses[DEFINING]
    description = require_comment(defining.comment, name=mnemonic, source=defining.source)
    decode = clauses.clauses[InstructionFunction.DECODE]
    encoding = parse_encoding(decode, function=InstructionFunction.DECODE, widths=widths)
    assembly = clauses.clauses[InstructionFunction.ASSEMBLY]
    syntax = parse_syntax(assembly)
    if syntax.split()[0] != mnemonic:
        raise SpecificationError(place(assembly.source), f"{mnemonic} is printed as {syntax}")

    definitions = tuple(
        clause_definition(function, clauses.clauses[function]) for function in InstructionFunction
    )
    instruction = Instruction(
        mnemonic=mnemonic,
        opcode=encoding.opcode,
        bits=format(encoding.opcode, f"0{encoding.opcode_width}b"),
        syntax=syntax,
        format=format_name(mnemonic, encoding),
        description=parse_prose(description, where=place(defining.source)),
        listing=Listing(definitions=definitions),
    )
    return InstructionFacts(instruction=instruction, encoding=encoding, source=decode.source)


def format_table(facts: Sequence[InstructionFacts]) -> FormatTable:
    """The formats that the instructions use, with the fields of each and its instructions."""

    formats = list[Format]()
    for name in FORMATS:
        members = sorted(
            (fact for fact in facts if fact.instruction.format == name),
            key=lambda fact: fact.encoding.opcode,
        )
        if not members:
            continue

        opcode = FormatField(label="opcode", width=members[0].encoding.opcode_width, code=False)
        fields = [opcode]
        for position, field in enumerate(members[0].encoding.fields):
            names = dict.fromkeys(fact.encoding.fields[position].name for fact in members)
            label = "0" * field.width if field.role is Role.PADDING else ", ".join(names)
            fields.append(FormatField(label=label, width=field.width, code=True))

        mnemonics = tuple(fact.instruction.mnemonic for fact in members)
        formats.append(Format(name=name, fields=tuple(fields), mnemonics=mnemonics))

    return FormatTable(formats=tuple(formats))


def opcode_table(facts: Sequence[InstructionFacts]) -> OpcodeTable:
    """The opcodes in order, with a gap for each run of opcodes that no instruction has."""

    width = facts[0].encoding.opcode_width
    rows = list[OpcodeRow | OpcodeGap]()
    following = 0
    for fact in sorted(facts, key=lambda fact: fact.encoding.opcode):
        instruction = fact.instruction
        if instruction.opcode < following:
            raise SpecificationError(
                place(fact.source), f"{instruction.mnemonic} has the opcode of another instruction"
            )

        if instruction.opcode > following:
            rows.append(OpcodeGap(first=following, last=instruction.opcode - 1))

        rows.append(
            OpcodeRow(
                opcode=instruction.opcode,
                mnemonic=instruction.mnemonic,
                syntax=instruction.syntax,
                format=instruction.format,
            )
        )
        following = instruction.opcode + 1

    if following < 1 << width:
        rows.append(OpcodeGap(first=following, last=(1 << width) - 1))

    return OpcodeTable(width=width, rows=tuple(rows))


def runs(opcodes: Iterable[int]) -> list[tuple[int, int]]:
    """The runs of consecutive numbers in `opcodes`, which are in order, as (first, last)."""

    found = list[tuple[int, int]]()
    for opcode in opcodes:
        if found and found[-1][1] == opcode - 1:
            found[-1] = (found[-1][0], opcode)
        else:
            found.append((opcode, opcode))

    return found


def describe_runs(found: Iterable[tuple[int, int]]) -> str:
    return " and ".join(str(a) if a == b else f"{a} to {b}" for a, b in found)


def generated(text: str) -> Prose:
    """Prose that the specification writes itself, in the subset of Markdown of the comments."""

    return parse_prose(text, where="the specification")


def opcode_section(table: OpcodeTable) -> Section:
    assigned = runs(row.opcode for row in table.rows if isinstance(row, OpcodeRow))
    gaps = [(row.first, row.last) for row in table.rows if isinstance(row, OpcodeGap)]
    summary = f"Opcodes {describe_runs(assigned)} are assigned"
    summary += f" and {describe_runs(gaps)} are not." if gaps else "."
    return Section(title="Opcodes", blocks=(generated(summary), table))


def format_section(table: FormatTable, opcode_width: int) -> Section:
    first, last = table.formats[0], table.formats[-1]
    summary = (
        f"Every instruction word starts with a {opcode_width}-bit opcode; the other "
        f"{first.width - opcode_width} bits are divided into fields by one of the formats "
        f"{first.name} to {last.name}. A field written as zeros is padding."
    )
    return Section(title="Instruction formats", blocks=(generated(summary), table))


def group_sections(
    facts: Sequence[InstructionFacts], by_file: Mapping[Path, list[Item]]
) -> tuple[Section, ...]:
    """A section for each file of instructions, in the order of their first instructions. It has
    the file's own prose, then its instructions."""

    groups = dict[Path, list[Instruction]]()
    for fact in facts:
        if fact.source.file.parent.name != GROUP_DIRECTORY:
            raise SpecificationError(
                place(fact.source),
                f"{fact.instruction.mnemonic} is outside {GROUP_DIRECTORY}/",
            )

        groups.setdefault(fact.source.file, []).append(fact.instruction)

    return tuple(
        Section(
            title=file.stem.replace("_", " ").capitalize(),
            blocks=(*blocks_of(by_file.get(file, [])), *instructions),
        )
        for file, instructions in groups.items()
    )


def section_files(by_file: Mapping[Path, list[Item]]) -> dict[str, Path]:
    """The files of the model that have a section each, by name."""

    files = {file.name: file for file in by_file if file.parent.name != GROUP_DIRECTORY}
    if unknown := files.keys() - SECTION_FILES.keys():
        raise SpecificationError(str(files[min(unknown)]), "has no place in the specification")

    if missing := SECTION_FILES.keys() - files.keys():
        raise SpecificationError(min(missing), "is not a file of the model with something to show")

    return files


def build_sections(bundle: Bundle) -> tuple[Section, ...]:
    instructions = find_instructions(bundle)
    widths = alias_widths(bundle.types)
    facts = [read_instruction(clauses, widths) for clauses in instructions]
    by_file = collect_items(bundle, consumed_clauses(instructions))
    files = section_files(by_file)

    formats, opcodes = format_table(facts), opcode_table(facts)
    subsections = (
        format_section(formats, opcodes.width),
        opcode_section(opcodes),
        *group_sections(facts, by_file),
    )
    return tuple(
        Section(
            title=title,
            blocks=blocks_of(by_file[files[name]]),
            sections=subsections if name == INSTRUCTION_SET else (),
        )
        for name, title in SECTION_FILES.items()
    )


def listing_of(block: Block) -> Listing | None:
    if isinstance(block, Described):
        return block.listing

    return block if isinstance(block, Listing) else None


def collect_symbols(sections: Iterable[Section]) -> dict[str, str]:
    """The anchor that each name refers to: those of the definitions and of the instructions."""

    symbols = dict[str, str]()

    def add(name: str, anchor: str) -> None:
        if symbols.setdefault(name, anchor) != anchor:
            raise SpecificationError(name, "names two things in the specification")

    for section in sections:
        for block in section.blocks:
            if (listing := listing_of(block)) is not None and listing.anchor is not None:
                for name in listing.names:
                    add(name, listing.anchor)
            elif isinstance(block, Instruction):
                add(block.mnemonic, block.anchor)

        symbols.update(collect_symbols(section.sections))

    return symbols


def build(bundle: Bundle) -> Specification:
    """The specification of the model whose definitions are in `bundle`."""

    sections = build_sections(bundle)
    return Specification(
        introduction=generated(INTRODUCTION), sections=sections, symbols=collect_symbols(sections)
    )
