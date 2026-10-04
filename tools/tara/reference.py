"""The reference model: TARA Studio's CPU, corrected to follow the RTL description.

TARA Studio's emulator (taracpu 1.2.2) implements TARA independently of the Sail model. Where it
departs from the RTL description, `Reference` overrides it; each override is one of the
discrepancies the README lists.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from enum import Enum, auto
from typing import override

from src.simulation.cpu import TaraCPU

from tara.assembly import Bare, Jump
from tara.emulator import RunOptions
from tara.isa import (
    ADDRESS_MASK,
    FRAMEBUFFER,
    INPUT_PORT,
    LINK_REGISTER,
    SCREEN_SIZE,
    WORD_BYTES,
    mnemonic,
)
from tara.transcript import CLEAR_PIXEL, SET_PIXEL, Status, TraceLine, Transcript

PIXELS_PER_BYTE = 8
ROW_BYTES = SCREEN_SIZE // PIXELS_PER_BYTE
PIXELS = str.maketrans("01", CLEAR_PIXEL + SET_PIXEL)


class Step(Enum):
    """The result of one step."""

    RETIRED = auto()
    ILLEGAL = auto()


@dataclass(eq=False, kw_only=True)
class StudioFault(Exception):
    """TARA Studio's CPU reported an error, which the corrections should make impossible."""

    pc: int
    message: str

    def __post_init__(self) -> None:
        super().__init__(f"TARA Studio's CPU failed at PC {self.pc:#06x}: {self.message}")


class Reference(TaraCPU):
    """TARA Studio's CPU with the RTL corrections, holding `memory` from address 0."""

    def __init__(self, memory: bytes) -> None:
        super().__init__()
        self.mem[: len(memory)] = memory
        self.keys = 0

    @override
    def read_byte(self, addr: int) -> int:
        """Correction: a byte read of the input port returns the input lines; stores to it still
        reach the RAM byte behind it."""

        address = addr & ADDRESS_MASK
        return self.keys if address == INPUT_PORT else self.mem[address]

    @override
    def read_word(self, addr: int) -> int:
        """Correction: word accesses ignore address bit 0 (word index = addr >> 1), and are two
        byte reads, so a word read at 0x5FE returns the input lines in its low byte."""

        even = addr & ADDRESS_MASK & ~1
        return self.read_byte(even) << 8 | self.read_byte(even + 1)

    @override
    def write_word(self, addr: int, val: int) -> None:
        """Correction: word accesses ignore address bit 0."""

        even = addr & ADDRESS_MASK & ~1
        self.mem[even : even + WORD_BYTES] = (val & 0xFFFF).to_bytes(WORD_BYTES)

    def advance(self) -> Step:
        """Fetch, decode and execute one instruction with the current input lines."""

        pc = self.pc
        name = mnemonic(self.read_word(pc))
        if name is None:
            # Correction: an unassigned opcode (27 to 31) still completes the fetch, which
            # advances PC, and then stops the run; Studio halts with an error instead.
            self.pc = (pc + WORD_BYTES) & ADDRESS_MASK
            return Step.ILLEGAL

        # Correction: Studio's step assumes an even PC (it cannot fetch at 0x7FF). Run it on the
        # aligned PC, then carry bit 0 into the next PC of everything but RET, whose target is
        # absolute.
        odd = pc & 1
        self.pc = pc - odd
        self.step(record_history=False)
        if self.error is not None:
            raise StudioFault(pc=pc, message=self.error)

        if name != Bare.Mnemonic.RET:
            self.pc = (self.pc + odd) & ADDRESS_MASK

        if name == Jump.Mnemonic.CALL:
            # Correction: the link is the masked PC + 2, like every PC value; Studio links 0x800
            # for a CALL at 0x7FE.
            self.reg[LINK_REGISTER] = (pc + WORD_BYTES) & ADDRESS_MASK

        return Step.RETIRED

    @property
    def framebuffer(self) -> tuple[str, ...]:
        """The framebuffer rows as `run --framebuffer` prints them, top row (y = 63) first; the
        most significant bit of a byte is its leftmost pixel."""

        rows = (FRAMEBUFFER + y * ROW_BYTES for y in reversed(range(SCREEN_SIZE)))
        return tuple(
            "".join(
                f"{byte:0{PIXELS_PER_BYTE}b}" for byte in self.mem[row : row + ROW_BYTES]
            ).translate(PIXELS)
            for row in rows
        )

    def run(self, options: RunOptions, *, disassembly: Sequence[str]) -> Transcript:
        """What `run` prints for this program with `options`. `disassembly` is the text of every
        word as the emulator under test's `disasm` prints it: the trace takes its assembly from
        there, since the model's syntax is not re-implemented here."""

        trace: list[TraceLine] = []
        retired = 0
        status = Status.HALTED
        while not self.halted:
            if retired == options.max_steps:
                status = Status.LIMIT
                break

            self.keys = int(options.keys.at(retired))  # Studio computes with what it reads
            pc, word = self.pc, self.read_word(self.pc)
            step = self.advance()
            trace.append(
                TraceLine(pc=pc, word=word, registers=tuple(self.reg), assembly=disassembly[word])
            )
            if step is Step.ILLEGAL:
                status = Status.ILLEGAL
                break

            retired += 1

        return Transcript(
            trace=tuple(trace) if options.trace else (),
            status=status,
            steps=retired,
            pc=self.pc,
            registers=tuple(self.reg),
            memory=bytes(self.mem),
            framebuffer=self.framebuffer if options.framebuffer else (),
        )
