"""Loadable image files: a program's memory from address 0, as raw bytes or hex words."""

import re
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from tara.isa import MEMORY_BYTES, WORD_BYTES

HEX_WORD = re.compile(r"[0-9A-Fa-f]{1,4}")


class ImageFormat(StrEnum):
    """Image encodings, named by their file suffix."""

    BIN = ".bin"
    HEX = ".hex"

    def render(self, words: Sequence[int]) -> bytes:
        """Encode instruction words, loaded from address 0, in this format."""

        match self:
            case ImageFormat.BIN:
                return b"".join(word.to_bytes(WORD_BYTES, "big") for word in words)
            case ImageFormat.HEX:
                return "".join(f"{word:04x}\n" for word in words).encode()

    def parse(self, contents: bytes) -> bytes:
        """The memory bytes an image in this format loads from address 0.

        Hex images hold 16-bit big-endian words of 1 to 4 hex digits; `;` starts a comment.
        """

        match self:
            case ImageFormat.BIN:
                memory = contents
            case ImageFormat.HEX:
                memory = b"".join(
                    parse_hex_word(token).to_bytes(WORD_BYTES, "big")
                    for line in contents.decode().splitlines()
                    for token in line.partition(";")[0].split()
                )

        if len(memory) > MEMORY_BYTES:
            raise ValueError(f"{len(memory)} bytes exceed the {MEMORY_BYTES}-byte memory")

        return memory


def parse_hex_word(token: str) -> int:
    """A word of a hex image."""

    if not HEX_WORD.fullmatch(token):
        raise ValueError(f"{token!r}: expected a word of 1 to 4 hex digits")

    return int(token, 16)


@dataclass(frozen=True)
class Image:
    """A loadable image file, encoded as its suffix says."""

    path: Path

    def __post_init__(self) -> None:
        if self.path.suffix not in ImageFormat:
            formats = " or ".join(ImageFormat)
            raise ValueError(f"{self.path}: expected a {formats} file")

    @property
    def format(self) -> ImageFormat:
        """The encoding selected by the file suffix."""

        return ImageFormat(self.path.suffix)

    def write(self, words: Sequence[int]) -> None:
        """Write instruction words, loaded from address 0, to this file."""

        self.path.write_bytes(self.format.render(words))

    def read(self) -> bytes:
        """The memory bytes this image loads from address 0."""

        return self.format.parse(self.path.read_bytes())
