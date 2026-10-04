"""What `run` prints: a line per step with --trace, the final state, and the framebuffer with
--framebuffer."""

import re
from collections.abc import Iterator
from dataclasses import dataclass
from enum import StrEnum, auto
from typing import Self

from tara.isa import MEMORY_BYTES, REGISTERS, SCREEN_SIZE

SET_PIXEL = "#"
CLEAR_PIXEL = "."
MEMORY_ROW_BYTES = 16


class Status(StrEnum):
    """How a run ended, as the status line spells it."""

    HALTED = auto()
    LIMIT = auto()
    ILLEGAL = auto()

    @property
    def exit_status(self) -> int:
        """The emulators' exit status for a run that ends this way."""

        return EXIT_STATUSES[self]


EXIT_STATUSES = {Status.HALTED: 0, Status.LIMIT: 3, Status.ILLEGAL: 4}

HEX16 = "[0-9a-f]{4}"
TRACE_LINE = re.compile(rf"({HEX16}) ({HEX16})((?: {HEX16}){{{REGISTERS}}}) (.+)")
STATUS_LINE = re.compile(rf"status ({'|'.join(Status)})")
STEPS_LINE = re.compile(r"steps (0|[1-9][0-9]*)")
PC_LINE = re.compile(rf"pc 0x({HEX16})")
REGISTER_LINE = re.compile(rf"r([0-7]) 0x({HEX16})")
MEMORY_LINE = re.compile(rf"mem ((?:[0-9a-f]{{2}}){{{MEMORY_BYTES}}})")
FRAMEBUFFER_LINE = re.compile(rf"fb ([{SET_PIXEL}{CLEAR_PIXEL}]{{{SCREEN_SIZE}}})")


class TranscriptError(ValueError):
    """Output that does not follow the output format."""


@dataclass(frozen=True, kw_only=True)
class TraceLine:
    """One step: its PC and instruction word, the registers after it, and its disassembly."""

    pc: int
    word: int
    registers: tuple[int, ...]
    assembly: str

    @classmethod
    def parse(cls, line: str) -> Self | None:
        """The step `line` spells, or None if it is not a trace line."""

        match = TRACE_LINE.fullmatch(line)
        if match is None:
            return None

        pc, word, registers, assembly = match.groups()
        return cls(
            pc=int(pc, 16),
            word=int(word, 16),
            registers=tuple(int(register, 16) for register in registers.split()),
            assembly=assembly,
        )

    def __str__(self) -> str:
        registers = " ".join(f"{register:04x}" for register in self.registers)
        return f"{self.pc:04x} {self.word:04x} {registers} {self.assembly}"


@dataclass(frozen=True, kw_only=True)
class Transcript:
    """Everything `run` prints; `framebuffer` holds its rows, top row (y = 63) first."""

    trace: tuple[TraceLine, ...]
    status: Status
    steps: int
    pc: int
    registers: tuple[int, ...]
    memory: bytes
    framebuffer: tuple[str, ...]

    @classmethod
    def parse(cls, text: str) -> Self:
        """The transcript `text` spells, which must follow the output format exactly."""

        lines = Lines(text)
        trace = tuple(lines.take_trace())
        status = Status(lines.expect(STATUS_LINE).group(1))
        steps = int(lines.expect(STEPS_LINE).group(1))
        pc = int(lines.expect(PC_LINE).group(1), 16)
        registers = tuple(lines.expect_register(index) for index in range(REGISTERS))
        memory = bytes.fromhex(lines.expect(MEMORY_LINE).group(1))
        framebuffer = tuple(lines.take_framebuffer())
        lines.expect_end()
        return cls(
            trace=trace,
            status=status,
            steps=steps,
            pc=pc,
            registers=registers,
            memory=memory,
            framebuffer=framebuffer,
        )

    def __str__(self) -> str:
        return "".join(f"{line}\n" for line in self.lines())

    def lines(self) -> list[str]:
        return self.lines_with_memory([f"mem {self.memory.hex()}"])

    def diffable_lines(self) -> list[str]:
        """The lines with the memory in rows of 16 bytes, each with its address, so that a diff
        of two transcripts points at the bytes that differ."""

        rows = range(0, len(self.memory), MEMORY_ROW_BYTES)
        return self.lines_with_memory(
            [
                f"mem 0x{row:03x} {self.memory[row : row + MEMORY_ROW_BYTES].hex(' ')}"
                for row in rows
            ]
        )

    def lines_with_memory(self, memory: list[str]) -> list[str]:
        return [
            *map(str, self.trace),
            f"status {self.status}",
            f"steps {self.steps}",
            f"pc 0x{self.pc:04x}",
            *(f"r{index} 0x{value:04x}" for index, value in enumerate(self.registers)),
            *memory,
            *(f"fb {row}" for row in self.framebuffer),
        ]

    @property
    def pixels(self) -> frozenset[tuple[int, int]]:
        """The (x, y) of every set pixel in the framebuffer rows; y = 0 is the bottom row."""

        return frozenset(
            (x, SCREEN_SIZE - 1 - row)
            for row, pixels in enumerate(self.framebuffer)
            for x, pixel in enumerate(pixels)
            if pixel == SET_PIXEL
        )


class Lines:
    """The lines of an output, consumed front to back."""

    def __init__(self, text: str) -> None:
        if not text.endswith("\n"):
            raise TranscriptError("the output does not end with a newline")

        self.lines = text.removesuffix("\n").split("\n")
        self.index = 0

    def peek(self) -> str | None:
        return self.lines[self.index] if self.index < len(self.lines) else None

    def take_trace(self) -> Iterator[TraceLine]:
        while (line := self.peek()) is not None and (step := TraceLine.parse(line)) is not None:
            self.index += 1
            yield step

    def take_framebuffer(self) -> Iterator[str]:
        while (line := self.peek()) is not None and (row := FRAMEBUFFER_LINE.fullmatch(line)):
            self.index += 1
            yield row.group(1)

    def expect(self, pattern: re.Pattern[str]) -> re.Match[str]:
        line = self.peek()
        match = None if line is None else pattern.fullmatch(line)
        if match is None:
            raise TranscriptError(
                f"line {self.index + 1}: expected {pattern.pattern}, got {line!r}"
            )

        self.index += 1
        return match

    def expect_register(self, index: int) -> int:
        number, value = self.expect(REGISTER_LINE).groups()
        if int(number) != index:
            raise TranscriptError(f"line {self.index}: expected r{index}, got r{number}")

        return int(value, 16)

    def expect_end(self) -> None:
        if (line := self.peek()) is not None:
            raise TranscriptError(f"line {self.index + 1}: unexpected {line!r}")
