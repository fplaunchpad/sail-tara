"""TARA assembly as typed values: an instruction is one of the formats below, each with its own
mnemonics, and `str()` of a program is its source, which TARA Studio's assembler accepts.
Programs have no labels: branch and jump offsets count instructions from the next one."""

from dataclasses import dataclass
from enum import StrEnum, auto


class Named(StrEnum):
    """A StrEnum whose members are spelled as their names (StrEnum's own auto lowercases them)."""

    @staticmethod
    def _generate_next_value_(name: str, start: int, count: int, last_values: list[str]) -> str:
        return name


class Register(Named):
    """A general-purpose register."""

    R0 = auto()
    R1 = auto()
    R2 = auto()
    R3 = auto()
    R4 = auto()
    R5 = auto()
    R6 = auto()
    R7 = auto()


def check_range(value: int, *, low: int, high: int) -> None:
    """Reject an immediate or an offset that does not fit its field."""

    if not low <= value <= high:
        raise ValueError(f"{value} is outside {low} to {high}")


@dataclass(frozen=True, kw_only=True)
class Bare:
    """An instruction without operands."""

    class Mnemonic(Named):
        NOP = auto()
        HLT = auto()
        RET = auto()

    mnemonic: Mnemonic

    def __str__(self) -> str:
        return self.mnemonic


@dataclass(frozen=True, kw_only=True)
class ThreeRegisters:
    """rd = rs1 op rs2."""

    class Mnemonic(Named):
        ADD = auto()
        SUB = auto()
        MUL = auto()
        AND = auto()
        OR = auto()
        XOR = auto()
        SLT = auto()

    mnemonic: Mnemonic
    rd: Register
    rs1: Register
    rs2: Register

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.rd}, {self.rs1}, {self.rs2}"


@dataclass(frozen=True, kw_only=True)
class TwoRegisters:
    """rd = op rs."""

    class Mnemonic(Named):
        MOV = auto()
        NOT = auto()

    mnemonic: Mnemonic
    rd: Register
    rs: Register

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.rd}, {self.rs}"


@dataclass(frozen=True, kw_only=True)
class Immediate:
    """A register and an unsigned 8-bit immediate."""

    class Mnemonic(Named):
        LIL = auto()
        LIH = auto()
        SHL = auto()
        SHR = auto()

    mnemonic: Mnemonic
    rd: Register
    value: int

    def __post_init__(self) -> None:
        check_range(self.value, low=0, high=0xFF)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.rd}, {self.value}"


@dataclass(frozen=True, kw_only=True)
class AddImmediate:
    """rd += a signed 8-bit immediate."""

    class Mnemonic(Named):
        ADDI = auto()

    mnemonic: Mnemonic = Mnemonic.ADDI
    rd: Register
    value: int

    def __post_init__(self) -> None:
        check_range(self.value, low=-0x80, high=0x7F)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.rd}, {self.value}"


@dataclass(frozen=True, kw_only=True)
class Memory:
    """A load into or a store from `register`, at a signed 5-bit offset from `base`."""

    class Mnemonic(Named):
        LDW = auto()
        STW = auto()
        LDB = auto()
        STB = auto()

    mnemonic: Mnemonic
    register: Register
    offset: int
    base: Register

    def __post_init__(self) -> None:
        check_range(self.offset, low=-0x10, high=0xF)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.register}, {self.offset}({self.base})"


@dataclass(frozen=True, kw_only=True)
class Branch:
    """A branch on `register`, `offset` instructions on from the next one."""

    class Mnemonic(Named):
        BZ = auto()
        BN = auto()

    mnemonic: Mnemonic
    register: Register
    offset: int

    def __post_init__(self) -> None:
        check_range(self.offset, low=-0x80, high=0x7F)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.register}, {self.offset}"


@dataclass(frozen=True, kw_only=True)
class Jump:
    """A jump or a call, `offset` instructions on from the next one."""

    class Mnemonic(Named):
        JMP = auto()
        CALL = auto()

    mnemonic: Mnemonic
    offset: int

    def __post_init__(self) -> None:
        check_range(self.offset, low=-0x400, high=0x3FF)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.offset}"


@dataclass(frozen=True, kw_only=True)
class Stack:
    """A push or a pop of `register`."""

    class Mnemonic(Named):
        PUSH = auto()
        POP = auto()

    mnemonic: Mnemonic
    register: Register

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.register}"


type Instruction = (
    Bare | ThreeRegisters | TwoRegisters | Immediate | AddImmediate | Memory | Branch | Jump | Stack
)


@dataclass(frozen=True)
class Program:
    """A TARA program; `str()` is its assembly source."""

    instructions: tuple[Instruction, ...]

    def __str__(self) -> str:
        return "".join(f"{instruction}\n" for instruction in self.instructions)
