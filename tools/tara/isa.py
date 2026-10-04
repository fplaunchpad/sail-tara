"""Facts about the TARA machine and instruction set, shared by the tools and the tests."""

from src.simulation.cpu import FMT, OP_NAME

MEMORY_BYTES = 2048
ADDRESS_MASK = MEMORY_BYTES - 1
WORD_BYTES = 2
WORDS = 1 << 16
REGISTERS = 8
LINK_REGISTER = 6
INPUT_PORT = 0x5FF
FRAMEBUFFER = 0x600
SCREEN_SIZE = 64
OPCODE_SHIFT = 11
ILLEGAL = "illegal"  # the disassembly of an unassigned opcode
CALL = "CALL"
RET = "RET"

# The bits each instruction format leaves unused: decoding ignores them, assembling clears them.
UNUSED_BITS = {"F0": 0x07FF, "F1": 0x0003, "F2": 0x001F, "F7": 0x00FF}


def mnemonic(word: int) -> str | None:
    """The mnemonic of the opcode in `word`, or None for the unassigned opcodes 27 to 31."""

    return OP_NAME.get(word >> OPCODE_SHIFT)


def canonical(word: int) -> int:
    """`word` with the bits its format leaves unused cleared: what assembling its disassembly
    gives, by TARA Studio's format table."""

    name = mnemonic(word)
    if name is None:
        raise ValueError(f"{word:#06x}: unassigned opcode")

    return word & ~UNUSED_BITS.get(FMT[name], 0)
