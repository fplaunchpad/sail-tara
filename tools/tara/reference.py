"""The reference model: TARA Studio's CPU, corrected to follow the RTL description.

TARA Studio's emulator (taracpu 1.2.2) is an implementation of TARA independent of the Sail
model. Where it departs from the RTL description, `Reference` overrides it; each override is one
of the discrepancies the README lists. The emulators must print exactly what `run` returns.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from enum import Enum, auto
from typing import override

from src.simulation.cpu import TaraCPU

from tara.isa import (
    ADDRESS_MASK,
    CALL,
    FRAMEBUFFER,
    INPUT_PORT,
    LINK_REGISTER,
    RET,
    SCREEN_SIZE,
    WORD_BYTES,
    mnemonic,
)
from tara.keys import KeySchedule
from tara.transcript import SET_PIXEL, Status, TraceLine, Transcript

DEFAULT_MAX_STEPS = 1_000_000
PIXELS_PER_BYTE = 8
CLEAR_PIXEL = "."


class Step(Enum):
    """The result of one step."""

    RETIRED = auto()
    ILLEGAL = auto()


@dataclass(eq=False)
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
        self.mem[even : even + WORD_BYTES] = (val & 0xFFFF).to_bytes(WORD_BYTES, "big")

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

        if name != RET:
            self.pc = (self.pc + odd) & ADDRESS_MASK

        if name == CALL:
            # Correction: the link is the masked PC + 2, like every PC value; Studio links 0x800
            # for a CALL at 0x7FE.
            self.reg[LINK_REGISTER] = (pc + WORD_BYTES) & ADDRESS_MASK

        return Step.RETIRED

    def pixel(self, x: int, y: int) -> bool:
        """Pixel (x, y) of the framebuffer; y = 0 is the bottom row."""

        byte = self.mem[FRAMEBUFFER + y * SCREEN_SIZE // PIXELS_PER_BYTE + x // PIXELS_PER_BYTE]
        return bool(byte >> (PIXELS_PER_BYTE - 1 - x % PIXELS_PER_BYTE) & 1)

    def framebuffer(self) -> tuple[str, ...]:
        """The framebuffer rows as the emulators print them, top row (y = 63) first."""

        return tuple(
            "".join(SET_PIXEL if self.pixel(x, y) else CLEAR_PIXEL for x in range(SCREEN_SIZE))
            for y in reversed(range(SCREEN_SIZE))
        )


def run(
    memory: bytes,
    *,
    keys: KeySchedule | None = None,
    max_steps: int | None = DEFAULT_MAX_STEPS,
    disassembly: Sequence[str] | None = None,
    framebuffer: bool = False,
) -> Transcript:
    """Run a program from power-on until it halts, `max_steps` instructions retire (None: no
    limit) or it fetches an unassigned opcode; what an emulator prints for that run.

    With `disassembly`, the text of every word as the emulator's `disasm` prints it, the
    transcript has a trace line per step: the model's assembly syntax is not re-implemented here.
    """

    schedule = keys or KeySchedule()
    machine = Reference(memory)
    steps: list[TraceLine] = []
    retired = 0
    status = Status.HALTED
    while not machine.halted:
        if retired == max_steps:
            status = Status.LIMIT
            break

        machine.keys = schedule.at(retired)
        pc, word = machine.pc, machine.read_word(machine.pc)
        result = machine.advance()
        if disassembly is not None:
            step = TraceLine(
                pc=pc, word=word, registers=tuple(machine.reg), assembly=disassembly[word]
            )
            steps.append(step)

        if result is Step.ILLEGAL:
            status = Status.ILLEGAL
            break

        retired += 1

    return Transcript(
        trace=tuple(steps),
        status=status,
        steps=retired,
        pc=machine.pc,
        registers=tuple(machine.reg),
        memory=bytes(machine.mem),
        framebuffer=machine.framebuffer() if framebuffer else (),
    )
