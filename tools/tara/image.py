"""Loadable image files: a program's memory from address 0, as raw bytes or as hex words."""

import re
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from tara.isa import MEMORY_BYTES, WORD_BYTES

HEX_WORD = re.compile(r"[0-9A-Fa-f]{1,4}")
COMMENT = ";"


class ImageFormat(StrEnum):
    """Image encodings, named by their file suffix."""

    BIN = ".bin"
    HEX = ".hex"

    def render(self, words: Sequence[int]) -> bytes:
        """`words`, loaded from address 0, in this format."""

        match self:
            case ImageFormat.BIN:
                return b"".join(word.to_bytes(WORD_BYTES) for word in words)
            case ImageFormat.HEX:
                return "".join(f"{word:04x}\n" for word in words).encode()

    def parse(self, contents: bytes) -> bytes:
        """The memory an image in this format loads from address 0. A hex image holds big-endian
        words of 1 to 4 hex digits, separated by whitespace; `;` starts a comment."""

        match self:
            case ImageFormat.BIN:
                memory = contents
            case ImageFormat.HEX:
                words: list[int] = []
                for line in contents.decode().splitlines():
                    for token in line.partition(COMMENT)[0].split():
                        if not HEX_WORD.fullmatch(token):
                            raise ValueError(f"{token!r}: expected a word of 1 to 4 hex digits")

                        words.append(int(token, 16))

                memory = ImageFormat.BIN.render(words)

        if len(memory) > MEMORY_BYTES:
            raise ValueError(f"{len(memory)} bytes exceed the {MEMORY_BYTES}-byte memory")

        return memory


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
        return ImageFormat(self.path.suffix)

    def write(self, words: Sequence[int]) -> None:
        """Write `words`, loaded from address 0."""

        self.path.write_bytes(self.format.render(words))

    def read(self) -> bytes:
        """The memory this image loads from address 0."""

        return self.format.parse(self.path.read_bytes())
