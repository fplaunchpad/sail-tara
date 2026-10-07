"""Documentation comments and evaluated examples share the extractor's versioned schema."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum, auto

import msgspec

from tara.asciidoc import Code
from tara.doc_operation import Expression, Operation, Rendering, Statement


class Category(StrEnum):
    USAGE = auto()
    ARCHITECTURE = auto()
    ASSUMPTION = auto()


class OperandDoc(msgspec.Struct, frozen=True, kw_only=True):
    name: str
    description: str


class Note(msgspec.Struct, frozen=True, kw_only=True):
    category: Category
    text: str


class State(msgspec.Struct, frozen=True, kw_only=True):
    register: str
    index: int | None
    value: str


class Observed(msgspec.Struct, frozen=True, kw_only=True):
    register: str
    label: str


class Context(msgspec.Struct, frozen=True, kw_only=True):
    runner: str
    arguments: tuple[str, ...]
    initial: tuple[State, ...]
    observed: tuple[Observed, ...]


class InstructionDoc(msgspec.Struct, frozen=True, kw_only=True):
    title: str
    operands: tuple[OperandDoc, ...]
    notes: tuple[Note, ...]
    related: tuple[str, ...]
    id: str | None


class Observation(msgspec.Struct, frozen=True, kw_only=True):
    name: str
    before: str
    after: str
    width: int | None


class Example(msgspec.Struct, frozen=True, kw_only=True):
    title: str
    assembly: str
    word: str
    observations: tuple[Observation, ...]
    retirement: str
    setup: tuple[State, ...]
    arguments: tuple[str, ...]


class MappingRule(msgspec.Struct, frozen=True, kw_only=True):
    direction: str
    input: str
    output: Expression
    guard: Expression | None

    def line(self) -> str:
        condition = (
            f" when {self.guard.render(Rendering.CARD).text}" if self.guard is not None else ""
        )
        return f"{self.direction}: {self.input}{condition} -> {self.output.render(Rendering.CARD).text}"

    @property
    def references(self) -> frozenset[str]:
        return self.output.references | (
            self.guard.references if self.guard is not None else set[str]()
        )


class Helper(msgspec.Struct, frozen=True, kw_only=True):
    name: str
    title: str
    signature: str
    description: str
    operation: tuple[Statement, ...]
    rules: tuple[MappingRule, ...]
    dependencies: tuple[str, ...]
    source_kind: str
    documented: bool
    source: str

    @property
    def anchor(self) -> str:
        return f"helper-{self.name}"

    @property
    def references(self) -> frozenset[str]:
        return Operation(statements=self.operation).references.union(
            *(rule.references for rule in self.rules)
        )


@dataclass(frozen=True, kw_only=True)
class Primitive:
    name: str
    title: str
    signature: str
    definition: str

    @property
    def anchor(self) -> str:
        return f"helper-{self.name}"

    def section(self) -> str:
        return f"[#{self.anchor}]\n=== `{self.name}` — {self.title}\n\n{Code(self.signature)}\n\n{self.definition}\n"


# Primitive semantics belong to the pinned Sail library. Width suffixes in operations instantiate n.
PRIMITIVES = (
    Primitive(
        name="signed",
        title="Signed interpretation",
        signature="signed_n(x: bits(n)) -> integer, n > 0",
        definition=(
            "Let u be the unsigned value of x. If its high bit is clear, return u; otherwise "
            "return u - 2^n. The result lies between -2^(n-1) and 2^(n-1)-1. This changes the "
            "interpretation, not the bits. For example, `signed8(0x80) = -128`."
        ),
    ),
    Primitive(
        name="unsigned",
        title="Unsigned interpretation",
        signature="unsigned_n(x: bits(n)) -> integer, n >= 0",
        definition=(
            "Return the sum of x[i] * 2^i over every bit i. The result lies between 0 and 2^n-1. "
            "For example, `unsigned16(0xFFFF) = 65535`."
        ),
    ),
    Primitive(
        name="sign_extend",
        title="Sign extension",
        signature="sign_extend_m(x: bits(n)) -> bits(m), 0 <= n <= m",
        definition=(
            "Keep x in the low n bits and fill every higher bit with x[n-1]. For an empty input, "
            "fill with zeros. For n > 0, the signed value is preserved. This is Sail's "
            "`sail_sign_extend(x, m)`.\n\n[[helper-sign_extend_16]]\n*`sign_extend_16`*: "
            "instantiate m = 16, with 0 ≤ n ≤ 16. `0x7F` (8 bits) becomes `0x007F`; `0x80` becomes "
            "`0xFF80`; `0xFF` becomes `0xFFFF`. The empty input becomes `0x0000`."
        ),
    ),
    Primitive(
        name="zero_extend",
        title="Zero extension",
        signature="zero_extend_m(x: bits(n)) -> bits(m), 0 <= n <= m",
        definition=(
            "Keep x in the low n bits and fill every higher bit with zero. The unsigned value is "
            "preserved. This is Sail's `sail_zero_extend(x, m)`. For example, "
            "`zero_extend_16(0xFF) = 0x00FF`."
        ),
    ),
    Primitive(
        name="wrap",
        title="Keep the low bits",
        signature="wrap_n(v: integer) -> bits(n), n >= 0",
        definition=(
            "Return v modulo 2^n as an n-bit vector. For example, `wrap16(65536) = 0x0000` and "
            "`wrap16(-1) = 0xFFFF`. This also describes `get_slice_int(n, v, 0)`."
        ),
    ),
    Primitive(
        name="integer_slice",
        title="Slice an integer",
        signature="integer_slice(v: integer, low: integer, n: integer) -> bits(n)",
        definition=(
            "For nonnegative low and n, return floor(v / 2^low) modulo 2^n. Bit i of the result is "
            "bit low+i of v. The source operation is `get_slice_int(n, v, low)`."
        ),
    ),
    Primitive(
        name="index",
        title="Select an element or bit",
        signature="v[i] -> element",
        definition=(
            "Select the element at index i, within the vector's bounds. Bit vectors are numbered "
            "with bit 0 least significant. The model uses decreasing vector order; register and "
            "memory indices still name the architectural register or byte directly."
        ),
    ),
    Primitive(
        name="slice",
        title="Select a bit range",
        signature="x[high:low] -> bits(high-low+1)",
        definition=(
            "Keep the inclusive bit range from high down to low, where 0 ≤ low ≤ high < width(x). "
            "The original low bit becomes result bit 0."
        ),
    ),
    Primitive(
        name="concat",
        title="Concatenate bits",
        signature="concat(a: bits(m), b: bits(n)) -> bits(m+n)",
        definition=(
            "Place a above b: a occupies the high m bits and b the low n bits. Its unsigned value "
            "is unsigned(a) * 2^n + unsigned(b)."
        ),
    ),
    Primitive(
        name="not_vec",
        title="Bitwise complement",
        signature="~x: bits(n) -> bits(n)",
        definition=(
            "Invert each of the n bits. The width stays n; the unsigned result is (2^n-1) XOR "
            "unsigned(x)."
        ),
    ),
    Primitive(
        name="shift_left",
        title="Logical left shift",
        signature="x << count: bits(n) -> bits(n), count >= 0",
        definition=(
            "Shift toward higher bit positions, fill low positions with zeros, and discard bits "
            "beyond width n. Equivalently, wrap_n(unsigned(x) * 2^count). Counts at least n "
            "produce zero."
        ),
    ),
    Primitive(
        name="shift_right",
        title="Logical right shift",
        signature="x >> count: bits(n) -> bits(n), count >= 0",
        definition=(
            "Shift toward lower bit positions and fill high positions with zeros. Equivalently, "
            "floor(unsigned(x) / 2^count), retaining width n. Counts at least n produce zero."
        ),
    ),
    Primitive(
        name="sail_zeros",
        title="Create zero bits",
        signature="sail_zeros(n: integer) -> bits(n), n >= 0",
        definition="Return an n-bit vector with every bit clear. The empty vector is allowed.",
    ),
    Primitive(
        name="length",
        title="Vector length",
        signature="length(x: vector(n, element)) -> integer",
        definition="Return n, the number of elements. For a bit vector this is its bit width.",
    ),
    Primitive(
        name="dec_str",
        title="Print an integer",
        signature="dec_str(value: integer) -> string",
        definition="Print the integer in base ten, with a minus sign for a negative value.",
    ),
    Primitive(
        name="concat_str",
        title="Concatenate text",
        signature="concat_str(a: string, b: string) -> string",
        definition=(
            "Append b after a. More than two arguments in a mapping rule abbreviate repeated "
            "concatenation in the displayed order."
        ),
    ),
    Primitive(
        name="dec_bits_3",
        title="Decimal three-bit mapping",
        signature="dec_bits_3(value: bits(3)) <-> string",
        definition=(
            "Print the unsigned value in decimal, from 0 through 7. Parsing accepts unsigned "
            "decimal digits representing a value in that range, including leading zeros, and "
            "returns the corresponding three bits."
        ),
    ),
    Primitive(
        name="dec_bits_8",
        title="Decimal eight-bit mapping",
        signature="dec_bits_8(value: bits(8)) <-> string",
        definition=(
            "Print the unsigned value in decimal, from 0 through 255. Parsing accepts unsigned "
            "decimal digits representing a value in that range, including leading zeros, and "
            "returns the corresponding eight bits."
        ),
    ),
    Primitive(
        name="execute",
        title="Instruction operation",
        signature="execute(insn: instruction) -> unit",
        definition=(
            "Run the ordered operation in the corresponding instruction entry. PC still holds this "
            "instruction's address; an operation can replace PC_next. The retirement helper "
            "subsequently commits PC."
        ),
    ),
    Primitive(
        name="retirement",
        title="Driver outcomes",
        signature="Retired | Stopped | Illegal(word)",
        definition=(
            "Retired means an instruction completed, including HLT. Stopped means the halt latch "
            "was already set and nothing changed. Illegal(word) means fetch found an unassigned "
            "encoding; PC advanced and the host decides what happens next."
        ),
    ),
    Primitive(
        name="encoding_match",
        title="Assigned encoding predicate",
        signature="encdec_backwards_matches(word) -> bool",
        definition=(
            "True exactly when the instruction encoding mapping accepts the word, including its "
            "guards. Fixed fields and constraints are shown in the encoding tables; ignored fields "
            "accept any bit pattern."
        ),
    ),
    Primitive(
        name="encdec_backwards",
        title="Decode an instruction",
        signature="encdec_backwards(word) -> instruction",
        definition=(
            "Apply the reverse of the instruction encoding mapping to an accepted word. Operand "
            "fields provide constructor arguments; ignored fields do not affect the instruction. "
            "The model checks the assigned-encoding predicate before calling this helper."
        ),
    ),
)
