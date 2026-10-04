"""Running an emulator executable that follows the shared command line."""

import subprocess
from dataclasses import dataclass
from pathlib import Path

from tara.isa import WORDS
from tara.transcript import Transcript, TranscriptError

TIMEOUT_SECONDS = 300
DISASSEMBLE_ALL = "--disasm-all"


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

    def run(self, *arguments: str | Path) -> Run:
        """Run with `arguments` and no input, and wait for it to exit."""

        completed = subprocess.run(
            [self.path, *arguments],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
        return Run(status=completed.returncode, stdout=completed.stdout, stderr=completed.stderr)

    def disassembly(self) -> tuple[str, ...]:
        """The assembly text of every word, as `--disasm-all` prints it, indexed by word."""

        run = self.run(DISASSEMBLE_ALL)
        if run.status != 0:
            raise TranscriptError(
                f"{DISASSEMBLE_ALL} exited with status {run.status}: {run.stderr}"
            )

        lines = run.stdout.splitlines()
        if len(lines) != WORDS:
            raise TranscriptError(f"{DISASSEMBLE_ALL} printed {len(lines)} lines, not {WORDS}")

        texts: list[str] = []
        for word, line in enumerate(lines):
            prefix = f"{word:04x} "
            if not line.startswith(prefix):
                raise TranscriptError(f"line {word + 1}: expected {prefix!r}, got {line!r}")

            texts.append(line.removeprefix(prefix))

        return tuple(texts)
