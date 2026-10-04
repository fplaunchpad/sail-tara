"""Random TARA programs: straight-line code with random operands, memory accesses through R7 and
forward branches, ending in HLT. Every one halts."""

import random
from enum import Enum, auto
from string.templatelib import Interpolation, Template

LENGTH = 200

# Random programs keep R7 as a pointer into a data page (0x400, 0x500 or 0x600), well clear of
# the code; only PUSH and POP move it. Every other instruction may use any register.
DATA_PAGES = (4, 5, 6)
DATA_REGISTERS = [f"R{index}" for index in range(7)]
REGISTERS = [*DATA_REGISTERS, "R7"]
SKIP_LIMIT = 8


class Operand(Enum):
    """A kind of operand in an instruction template, filled with a fresh random value at each
    use."""

    PAGE = auto()  # the data page R7 points into
    DATA = auto()  # a register other than R7
    REGISTER = auto()  # any register
    BYTE = auto()
    SIGNED_BYTE = auto()
    OFFSET = auto()  # a 5-bit offset from R7
    SKIP = auto()  # a forward branch distance that stays within the program

    def sample(self, rng: random.Random, remaining: int) -> str:
        match self:
            case Operand.PAGE:
                return str(rng.choice(DATA_PAGES))
            case Operand.DATA:
                return rng.choice(DATA_REGISTERS)
            case Operand.REGISTER:
                return rng.choice(REGISTERS)
            case Operand.BYTE:
                return str(rng.randint(0, 0xFF))
            case Operand.SIGNED_BYTE:
                return str(rng.randint(-0x80, 0x7F))
            case Operand.OFFSET:
                return str(rng.randint(-0x10, 0xF))
            case Operand.SKIP:
                return str(rng.randint(0, min(SKIP_LIMIT, remaining)))


PAGE, DATA, REGISTER, BYTE, SIGNED_BYTE, OFFSET, SKIP = Operand
PROLOGUE = (t"LIL R7, 0", t"LIH R7, {PAGE}")
EPILOGUE = t"HLT"
TEMPLATES = (
    t"ADD {DATA}, {REGISTER}, {REGISTER}",
    t"SUB {DATA}, {REGISTER}, {REGISTER}",
    t"MUL {DATA}, {REGISTER}, {REGISTER}",
    t"AND {DATA}, {REGISTER}, {REGISTER}",
    t"OR {DATA}, {REGISTER}, {REGISTER}",
    t"XOR {DATA}, {REGISTER}, {REGISTER}",
    t"SLT {DATA}, {REGISTER}, {REGISTER}",
    t"MOV {DATA}, {REGISTER}",
    t"NOT {DATA}, {REGISTER}",
    t"LIL {DATA}, {BYTE}",
    t"LIH {DATA}, {BYTE}",
    t"SHL {DATA}, {BYTE}",
    t"SHR {DATA}, {BYTE}",
    t"ADDI {DATA}, {SIGNED_BYTE}",
    t"LDW {DATA}, {OFFSET}(R7)",
    t"LDB {DATA}, {OFFSET}(R7)",
    t"STW {REGISTER}, {OFFSET}(R7)",
    t"STB {REGISTER}, {OFFSET}(R7)",
    t"PUSH {REGISTER}",
    t"POP {DATA}",
    t"BZ {REGISTER}, {SKIP}",
    t"BN {REGISTER}, {SKIP}",
    t"JMP {SKIP}",
    t"NOP",
)


def random_program(rng: random.Random) -> str:
    """Straight-line code with random operands, memory accesses through R7 and forward
    branches, ending in HLT."""

    body = (rng.choice(TEMPLATES) for _ in range(LENGTH))
    templates = [*PROLOGUE, *body, EPILOGUE]
    # A branch may skip at most the instructions between it and the final HLT.
    lines = (
        fill(template, rng, len(templates) - 2 - index) for index, template in enumerate(templates)
    )
    return "".join(f"{line}\n" for line in lines)


def fill(template: Template, rng: random.Random, remaining: int) -> str:
    """The instruction `template` spells, with a fresh random value for each operand."""

    return "".join(
        part if isinstance(part, str) else operand(part).sample(rng, remaining) for part in template
    )


def operand(part: Interpolation[object]) -> Operand:
    if not isinstance(part.value, Operand):
        raise TypeError(f"{{{part.expression}}} is not an operand")

    return part.value
