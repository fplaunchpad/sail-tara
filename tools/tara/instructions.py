"""What the clauses of an instruction say about it: its opcode, its fields and its syntax.

The model gives these once, in the clauses of `decode` and `assembly`; the specification reads them
from there instead of repeating them. The names of the formats, F0 to F7, are the TARA Studio
manual's: the model does not name its layouts, so this module does.
"""

import re
from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum, auto

import click

from tara.sail_doc import Clause, TypeDefinition


class Role(StrEnum):
    """What a field of an instruction word holds."""

    REGISTER = auto()
    IMMEDIATE = auto()
    OFFSET = auto()
    PADDING = auto()


# The type of the register fields, and the names of the offset and padding fields.
REGISTER_TYPE = "regidx"
OFFSET_FIELD = "off"
PADDING_FIELD = "_"

BINARY = "0b"
HEXADECIMAL = "0x"
BITS_TYPE = re.compile(r"bits\((?P<width>\d+)\)")
ALIAS = re.compile(r"type (?P<name>\w+) = bits\((?P<width>\d+)\)")
FIELD = re.compile(r"(?P<name>\w+) : (?P<type>.+)")
SOME = re.compile(r"Some\((?P<mnemonic>\w+)\(")
BARE_SYNTAX = re.compile(r'"(?P<mnemonic>[A-Z]+)"')
CALL_SYNTAX = re.compile(r'op[123]\("(?P<mnemonic>[A-Z]+)", (?P<operands>.+)\)', re.S)
OPERAND_SYNTAX = (
    (re.compile(r"reg\((?P<a>\w+)\)"), "{a}"),
    (re.compile(r"dec_str\((?:un)?signed\((?P<a>\w+)\)\)"), "{a}"),
    (re.compile(r"mem\((?P<a>\w+), (?P<b>\w+)\)"), "{a}({b})"),
)
OPENING = "([{"
CLOSING = ")]}"


@dataclass(eq=False)
class UnsupportedClause(click.ClickException):
    """A clause of an instruction that the specification cannot read."""

    clause: Clause
    problem: str

    def __post_init__(self) -> None:
        source = self.clause.source
        super().__init__(f"{source.file}:{source.line}: {self.problem}: {source.text}")


@dataclass(eq=False)
class UnknownFormat(click.ClickException):
    """The fields of an instruction match none of the formats."""

    mnemonic: str
    layout: tuple[tuple[Role, int], ...]

    def __post_init__(self) -> None:
        fields = ", ".join(f"{role} {width}" for role, width in self.layout)
        super().__init__(f"{self.mnemonic}: no format has the fields {fields}")


@dataclass(frozen=True, kw_only=True)
class Field:
    """A field of an instruction word after the opcode, such as `rd` or the padding."""

    name: str
    role: Role
    width: int


type Layout = tuple[tuple[Role, int], ...]


@dataclass(frozen=True, kw_only=True)
class Encoding:
    """The opcode and the fields that follow it, as a clause of `decode` matches them."""

    opcode: int
    opcode_width: int
    fields: tuple[Field, ...]

    @property
    def layout(self) -> Layout:
        return tuple((field.role, field.width) for field in self.fields)


REG, IMM, OFF, PAD = Role.REGISTER, Role.IMMEDIATE, Role.OFFSET, Role.PADDING

# The formats of the TARA Studio manual, by their fields after the opcode: a register is 3 bits,
# and an immediate, an offset or padding, which `decode` ignores, has the width given.
FORMATS: Mapping[str, Layout] = {
    "F0": ((PAD, 11),),
    "F1": ((REG, 3), (REG, 3), (REG, 3), (PAD, 2)),
    "F2": ((REG, 3), (REG, 3), (PAD, 5)),
    "F3": ((REG, 3), (IMM, 8)),
    "F4": ((REG, 3), (REG, 3), (OFF, 5)),
    "F5": ((REG, 3), (OFF, 8)),
    "F6": ((OFF, 11),),
    "F7": ((REG, 3), (PAD, 8)),
}


def format_name(mnemonic: str, encoding: Encoding) -> str:
    """The name of the format of the instruction `mnemonic`, which decodes as `encoding`."""

    for name, layout in FORMATS.items():
        if layout == encoding.layout:
            return name

    raise UnknownFormat(mnemonic, encoding.layout)


def split_top_level(text: str, separator: str) -> list[str]:
    """The parts of `text` between the `separator`s that are outside any brackets."""

    parts = list[str]()
    depth = 0
    start = 0
    for index, character in enumerate(text):
        if character in OPENING:
            depth += 1
        elif character in CLOSING:
            depth -= 1
        elif character == separator and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1

    parts.append(text[start:].strip())
    return parts


def alias_widths(types: Mapping[str, TypeDefinition]) -> dict[str, int]:
    """The widths of the types that are named bit-vectors, such as `type regidx = bits(3)`."""

    widths = dict[str, int]()
    for name, definition in types.items():
        if (match := ALIAS.fullmatch(definition.source.text)) is not None:
            widths[name] = int(match["width"])

    return widths


def literal_width(literal: str) -> int | None:
    """The width in bits of the bit-vector literal `literal`, or None when it is not one."""

    digits = literal[len(BINARY) :]
    if literal.startswith(BINARY) and digits and set(digits) <= {"0", "1"}:
        return len(digits)

    digits = literal[len(HEXADECIMAL) :]
    if literal.startswith(HEXADECIMAL) and digits:
        return 4 * len(digits)

    return None


def clause_argument(clause: Clause, *, function: str) -> str:
    """The text between the parentheses of `function clause FUNCTION(...)` in `clause`."""

    text = clause.source.text
    head = f"function clause {function}("
    if not text.startswith(head):
        raise UnsupportedClause(clause, f"does not start with {head!r}")

    depth = 1
    for index in range(len(head), len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1

        if depth == 0:
            return text[len(head) : index]

    raise UnsupportedClause(clause, "has an unclosed parenthesis")


def parse_encoding(clause: Clause, *, function: str, widths: Mapping[str, int]) -> Encoding:
    """The encoding in the clause of `function` that matches the bits of a word, which has the form
    `function clause decode(0b01001 @ rd : regidx @ ... @ _ : bits(2)) = ...`; `widths` are the
    widths of the types it names."""

    items = split_top_level(clause_argument(clause, function=function), "@")
    opcode_width = literal_width(items[0])
    if opcode_width is None:
        raise UnsupportedClause(clause, "does not start with the opcode as a literal")

    fields = list[Field]()
    for item in items[1:]:
        if (field := FIELD.fullmatch(item)) is None:
            raise UnsupportedClause(clause, f"has the field {item!r}, which has no type")

        name, type_name = field["name"], field["type"]
        if (bits := BITS_TYPE.fullmatch(type_name)) is not None:
            width = int(bits["width"])
        elif type_name in widths:
            width = widths[type_name]
        else:
            raise UnsupportedClause(clause, f"has a field of the unknown type {type_name!r}")

        if name == PADDING_FIELD:
            role = Role.PADDING
        elif name == OFFSET_FIELD:
            role = Role.OFFSET
        elif type_name == REGISTER_TYPE:
            role = Role.REGISTER
        else:
            role = Role.IMMEDIATE

        fields.append(Field(name=name, role=role, width=width))

    return Encoding(opcode=int(items[0], 0), opcode_width=opcode_width, fields=tuple(fields))


def decoded_mnemonic(clause: Clause) -> str | None:
    """The constructor that a clause of `decode` returns, from its body `Some(ADD(rd, rs1, rs2))`;
    None for a body that is not `Some(...)`, such as the `None()` of the unassigned opcodes."""

    match = SOME.match(clause.body.text)
    return None if match is None else match["mnemonic"]


def parse_syntax(clause: Clause) -> str:
    """The syntax of an instruction from its clause of `assembly`: the mnemonic, then the operands,
    such as `ADD rd, rs1, rs2` or `LDW rd, off(base)`."""

    body = clause.body.text
    if (bare := BARE_SYNTAX.fullmatch(body)) is not None:
        return bare["mnemonic"]

    if (call := CALL_SYNTAX.fullmatch(body)) is None:
        raise UnsupportedClause(clause, "is neither a mnemonic nor a call of op1, op2 or op3")

    operands = list[str]()
    for operand in split_top_level(call["operands"], ","):
        for pattern, template in OPERAND_SYNTAX:
            if (match := pattern.fullmatch(operand)) is not None:
                operands.append(template.format(**match.groupdict()))
                break
        else:
            raise UnsupportedClause(clause, f"has the operand {operand!r}, which is not known")

    return f"{call['mnemonic']} {', '.join(operands)}"
