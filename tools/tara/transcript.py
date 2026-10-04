"""What a batch run of an emulator prints: trace lines, the final state, the framebuffer."""

import re
from collections.abc import Iterator
from dataclasses import dataclass
from enum import StrEnum, auto
from typing import Self

from tara.isa import MEMORY_BYTES, REGISTERS, SCREEN_SIZE

HEX16 = "[0-9a-f]{4}"
TRACE_LINE = re.compile(rf"({HEX16}) ({HEX16})((?: {HEX16}){{{REGISTERS}}}) (.+)")
STATUS_LINE = re.compile(r"status (halted|limit|illegal)")
STEPS_LINE = re.compile(r"steps (0|[1-9][0-9]*)")
PC_LINE = re.compile(rf"pc 0x({HEX16})")
REGISTER_LINE = re.compile(rf"r([0-7]) 0x({HEX16})")
MEMORY_LINE = re.compile(rf"mem ((?:[0-9a-f]{{2}}){{{MEMORY_BYTES}}})")
FRAMEBUFFER_LINE = re.compile(rf"fb ([#.]{{{SCREEN_SIZE}}})")
SET_PIXEL = "#"
MEMORY_ROW_BYTES = 16


class Status(StrEnum):
    """Why a run ended, as the status line spells it."""

    HALTED = auto()
    LIMIT = auto()
    ILLEGAL = auto()


# The emulators' exit status for each way a run ends.
EXIT_STATUSES = {Status.HALTED: 0, Status.LIMIT: 3, Status.ILLEGAL: 4}


class TranscriptError(ValueError):
    """Output that does not follow the emulators' output format."""


@dataclass(frozen=True, kw_only=True)
class TraceLine:
    """One step: its PC and instruction word, the registers after it, and its assembly."""

    pc: int
    word: int
    registers: tuple[int, ...]
    assembly: str

    @classmethod
    def parse(cls, line: str) -> Self | None:
        """The trace line `line` spells, or None if it is not one."""

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

    def render(self) -> str:
        registers = " ".join(f"{register:04x}" for register in self.registers)
        return f"{self.pc:04x} {self.word:04x} {registers} {self.assembly}"


@dataclass(frozen=True, kw_only=True)
class Transcript:
    """Everything a batch run prints, parsed: the trace lines (with -t), the final state, and the
    framebuffer rows (with --framebuffer), top row (y = 63) first."""

    trace: tuple[TraceLine, ...]
    status: Status
    steps: int
    pc: int
    registers: tuple[int, ...]
    memory: bytes
    framebuffer: tuple[str, ...]

    @classmethod
    def parse(cls, text: str) -> Self:
        """Parse an emulator's standard output, which must follow the format exactly."""

        if not text.endswith("\n"):
            raise TranscriptError("the output does not end with a newline")

        lines = Lines(text.removesuffix("\n").split("\n"))
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

    def render(self) -> str:
        """The output this transcript stands for."""

        return "".join(f"{line}\n" for line in self.lines())

    def lines(self, *, memory_rows: bool = False) -> list[str]:
        """The output lines; with `memory_rows`, the memory line split into rows of 16 bytes
        with their addresses, so that a diff of two transcripts points at the bytes."""

        lines = [step.render() for step in self.trace]
        lines += [f"status {self.status}", f"steps {self.steps}", f"pc 0x{self.pc:04x}"]
        lines += [f"r{index} 0x{value:04x}" for index, value in enumerate(self.registers)]
        if memory_rows:
            lines += [
                f"mem 0x{address:03x} {self.memory[address : address + MEMORY_ROW_BYTES].hex(' ')}"
                for address in range(0, len(self.memory), MEMORY_ROW_BYTES)
            ]
        else:
            lines.append(f"mem {self.memory.hex()}")

        lines += [f"fb {row}" for row in self.framebuffer]
        return lines

    @property
    def exit_status(self) -> int:
        """The emulators' exit status for this run."""

        return EXIT_STATUSES[self.status]

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
    """Output lines, consumed front to back by the parser."""

    def __init__(self, lines: list[str]) -> None:
        self.lines = lines
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
