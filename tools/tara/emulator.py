"""Running an emulator executable that follows the shared command line: the subcommands
`run` (a program to its end), `play` (in the terminal) and `disasm` (every word)."""

import subprocess
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from tara.isa import WORDS
from tara.transcript import Transcript, TranscriptError

TIMEOUT_SECONDS = 300

# The emulators' subcommands.
Subcommand = StrEnum("Subcommand", "RUN PLAY DISASM")


@dataclass(frozen=True, kw_only=True)
class Run:
    """An emulator's exit status and output."""

    status: int
    stdout: str
    stderr: str

    @property
    def transcript(self) -> Transcript:
        """The standard output, parsed; it must follow the output format exactly."""

        try:
            return Transcript.parse(self.stdout)
        except TranscriptError as error:
            raise TranscriptError(f"{error} (exit status {self.status}; {self.stderr!r})") from None


@dataclass(frozen=True)
class Emulator:
    """An emulator executable (tara-c, tara-ocaml) that follows the shared command line."""

    path: Path

    @property
    def name(self) -> str:
        return self.path.name

    def invoke(self, *arguments: str | Path) -> Run:
        """Start the emulator with `arguments` and no input, and wait for it to exit."""

        completed = subprocess.run(
            [self.path, *arguments],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
        return Run(status=completed.returncode, stdout=completed.stdout, stderr=completed.stderr)

    def run(self, *arguments: str | Path) -> Run:
        """`run` a program with `arguments`: the options, then the image."""

        return self.invoke(Subcommand.RUN, *arguments)

    def disasm(self) -> Run:
        """`disasm`: the assembly text of every word."""

        return self.invoke(Subcommand.DISASM)

    def disassembly(self) -> tuple[str, ...]:
        """The assembly text of every word, as `disasm` prints it, indexed by word."""

        run = self.disasm()
        if run.status != 0:
            raise TranscriptError(f"disasm exited with status {run.status}: {run.stderr}")

        lines = run.stdout.splitlines()
        if len(lines) != WORDS:
            raise TranscriptError(f"disasm printed {len(lines)} lines, not {WORDS}")

        texts: list[str] = []
        for word, line in enumerate(lines):
            prefix = f"{word:04x} "
            if not line.startswith(prefix):
                raise TranscriptError(f"line {word + 1}: expected {prefix!r}, got {line!r}")

            texts.append(line.removeprefix(prefix))

        return tuple(texts)
