"""An emulator executable that follows the shared command line: the subcommands `run` (a program
to its end), `play` (in the terminal) and `disasm` (every word)."""

import subprocess
import tempfile
from dataclasses import dataclass, field
from enum import StrEnum, auto
from pathlib import Path

from tara.isa import WORDS
from tara.keys import KeySchedule
from tara.transcript import Transcript, TranscriptError

TIMEOUT_SECONDS = 300
DEFAULT_MAX_STEPS = 1_000_000
ERROR_STATUS = 1


class Subcommand(StrEnum):
    """The emulators' subcommands."""

    RUN = auto()
    PLAY = auto()
    DISASM = auto()


@dataclass(frozen=True, kw_only=True)
class RunOptions:
    """The options of `run`, which the reference model takes too."""

    trace: bool = False
    max_steps: int | None = DEFAULT_MAX_STEPS  # None: no limit
    keys: KeySchedule = field(default_factory=KeySchedule)
    framebuffer: bool = False

    def arguments(self, *, key_script: Path) -> list[str | Path]:
        """The options on the command line; `key_script` holds `keys.script()`."""

        arguments: list[str | Path] = ["--max-steps", str(self.max_steps or 0)]
        arguments += ["--keys", str(self.keys.initial)]
        if self.keys.changes:
            arguments += ["--key-script", key_script]

        if self.trace:
            arguments.append("--trace")

        if self.framebuffer:
            arguments.append("--framebuffer")

        return arguments


@dataclass(frozen=True, kw_only=True)
class Run:
    """An emulator's exit status and output."""

    status: int
    stdout: str
    stderr: str

    @property
    def rejected(self) -> bool:
        """Whether the emulator rejected its arguments or input: exit status 1, a message on
        stderr and nothing on stdout."""

        return self.status == ERROR_STATUS and not self.stdout and bool(self.stderr.strip())

    @property
    def transcript(self) -> Transcript:
        """The standard output of `run`, parsed. It must follow the output format exactly, and
        the exit status must agree with its status line."""

        try:
            transcript = Transcript.parse(self.stdout)
        except TranscriptError as error:
            raise TranscriptError(f"{error} (exit status {self.status}; {self.stderr!r})") from None

        if self.status != transcript.status.exit_status:
            raise TranscriptError(f"exit status {self.status} after status {transcript.status}")

        return transcript


@dataclass(frozen=True)
class Emulator:
    """An emulator executable (tara-c, tara-ocaml, tara-verilator)."""

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

    def run(self, image: Path, options: RunOptions) -> Run:
        """`run` the program in `image` with `options`."""

        with tempfile.TemporaryDirectory() as directory:
            key_script = Path(directory) / "keys"
            key_script.write_text(options.keys.script())
            return self.invoke(Subcommand.RUN, *options.arguments(key_script=key_script), image)

    def disassembly(self) -> tuple[str, ...]:
        """The text of every word as `disasm` prints it, indexed by word."""

        run = self.invoke(Subcommand.DISASM)
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
