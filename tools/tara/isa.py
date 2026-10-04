"""Facts about the TARA machine and instruction set."""

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

# The bits each of TARA Studio's instruction formats leaves unused.
UNUSED_BITS = {"F0": 0x07FF, "F1": 0x0003, "F2": 0x001F, "F7": 0x00FF}


def mnemonic(word: int) -> str | None:
    """The mnemonic of the opcode in `word`, or None for the unassigned opcodes 27 to 31."""

    return OP_NAME.get(word >> OPCODE_SHIFT)


def canonical(word: int) -> int:
    """`word`, which holds an assigned opcode, with the bits its format leaves unused cleared:
    decoding ignores them, so assembling the word's disassembly gives this."""

    return word & ~UNUSED_BITS.get(FMT[OP_NAME[word >> OPCODE_SHIFT]], 0)
