"""TARA assembly as typed values: an instruction is one of the formats below, and `str()` of a
program is its source, which TARA Studio's assembler accepts. Programs have no labels: branch and
jump offsets count instructions from the one after the branch."""

from dataclasses import dataclass
from enum import StrEnum, auto
from typing import ClassVar


class Named(StrEnum):
    """A StrEnum whose members are spelled as their names."""

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


class Mnemonic(Named):
    """An instruction's mnemonic."""

    NOP = auto()
    HLT = auto()
    MOV = auto()
    LIL = auto()
    LIH = auto()
    LDW = auto()
    STW = auto()
    LDB = auto()
    STB = auto()
    ADD = auto()
    SUB = auto()
    ADDI = auto()
    MUL = auto()
    AND = auto()
    OR = auto()
    XOR = auto()
    NOT = auto()
    SHL = auto()
    SHR = auto()
    SLT = auto()
    BZ = auto()
    BN = auto()
    JMP = auto()
    CALL = auto()
    RET = auto()
    PUSH = auto()
    POP = auto()


def check(
    mnemonic: Mnemonic, allowed: frozenset[Mnemonic], value: int = 0, low: int = 0, high: int = 0
) -> None:
    """Reject a mnemonic of another format, or an immediate or offset outside its field."""

    if mnemonic not in allowed:
        raise ValueError(f"{mnemonic} does not take these operands")

    if not low <= value <= high:
        raise ValueError(f"{mnemonic}: {value} is outside {low} to {high}")


@dataclass(frozen=True, kw_only=True)
class Bare:
    """An instruction without operands."""

    MNEMONICS: ClassVar = frozenset({Mnemonic.NOP, Mnemonic.HLT, Mnemonic.RET})

    mnemonic: Mnemonic

    def __post_init__(self) -> None:
        check(self.mnemonic, allowed=self.MNEMONICS)

    def __str__(self) -> str:
        return self.mnemonic


@dataclass(frozen=True, kw_only=True)
class ThreeRegisters:
    """rd = rs1 op rs2."""

    MNEMONICS: ClassVar = frozenset(
        {Mnemonic.ADD, Mnemonic.SUB, Mnemonic.MUL, Mnemonic.AND, Mnemonic.OR, Mnemonic.XOR}
        | {Mnemonic.SLT}
    )

    mnemonic: Mnemonic
    rd: Register
    rs1: Register
    rs2: Register

    def __post_init__(self) -> None:
        check(self.mnemonic, allowed=self.MNEMONICS)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.rd}, {self.rs1}, {self.rs2}"


@dataclass(frozen=True, kw_only=True)
class TwoRegisters:
    """rd = op rs."""

    MNEMONICS: ClassVar = frozenset({Mnemonic.MOV, Mnemonic.NOT})

    mnemonic: Mnemonic
    rd: Register
    rs: Register

    def __post_init__(self) -> None:
        check(self.mnemonic, allowed=self.MNEMONICS)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.rd}, {self.rs}"


@dataclass(frozen=True, kw_only=True)
class Immediate:
    """A register and an 8-bit immediate: signed for ADDI, unsigned otherwise."""

    MNEMONICS: ClassVar = frozenset(
        {Mnemonic.LIL, Mnemonic.LIH, Mnemonic.ADDI, Mnemonic.SHL, Mnemonic.SHR}
    )

    mnemonic: Mnemonic
    rd: Register
    value: int

    def __post_init__(self) -> None:
        low, high = (-0x80, 0x7F) if self.mnemonic is Mnemonic.ADDI else (0, 0xFF)
        check(self.mnemonic, allowed=self.MNEMONICS, value=self.value, low=low, high=high)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.rd}, {self.value}"


@dataclass(frozen=True, kw_only=True)
class Memory:
    """A load into or a store from `register`, at a signed 5-bit offset from `base`."""

    MNEMONICS: ClassVar = frozenset({Mnemonic.LDW, Mnemonic.STW, Mnemonic.LDB, Mnemonic.STB})

    mnemonic: Mnemonic
    register: Register
    offset: int
    base: Register

    def __post_init__(self) -> None:
        check(self.mnemonic, allowed=self.MNEMONICS, value=self.offset, low=-0x10, high=0xF)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.register}, {self.offset}({self.base})"


@dataclass(frozen=True, kw_only=True)
class Branch:
    """A branch on `register`, `offset` instructions on from the next one."""

    MNEMONICS: ClassVar = frozenset({Mnemonic.BZ, Mnemonic.BN})

    mnemonic: Mnemonic
    register: Register
    offset: int

    def __post_init__(self) -> None:
        check(self.mnemonic, allowed=self.MNEMONICS, value=self.offset, low=-0x80, high=0x7F)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.register}, {self.offset}"


@dataclass(frozen=True, kw_only=True)
class Jump:
    """A jump or a call, `offset` instructions on from the next one."""

    MNEMONICS: ClassVar = frozenset({Mnemonic.JMP, Mnemonic.CALL})

    mnemonic: Mnemonic
    offset: int

    def __post_init__(self) -> None:
        check(self.mnemonic, allowed=self.MNEMONICS, value=self.offset, low=-0x400, high=0x3FF)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.offset}"


@dataclass(frozen=True, kw_only=True)
class Stack:
    """A push or a pop of `register`."""

    MNEMONICS: ClassVar = frozenset({Mnemonic.PUSH, Mnemonic.POP})

    mnemonic: Mnemonic
    register: Register

    def __post_init__(self) -> None:
        check(self.mnemonic, allowed=self.MNEMONICS)

    def __str__(self) -> str:
        return f"{self.mnemonic} {self.register}"


type Instruction = Bare | ThreeRegisters | TwoRegisters | Immediate | Memory | Branch | Jump | Stack


@dataclass(frozen=True)
class Program:
    """A TARA program; `str()` is its assembly source."""

    instructions: tuple[Instruction, ...]

    def __str__(self) -> str:
        return "".join(f"{instruction}\n" for instruction in self.instructions)
