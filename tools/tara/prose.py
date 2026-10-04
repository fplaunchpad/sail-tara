"""Documentation comments as prose: paragraphs and bullet lists of text and code.

The comments of the model (`/*! ... */`) are written in a small subset of Markdown, which is what
Sail's own documentation backends handle without trouble:

- paragraphs are separated by blank lines;
- a line that starts with `- ` or `* ` begins an item of a bullet list, and the lines after it, up
  to the next item or a blank line, continue the item (Sail's own Markdown printer writes `*`);
- `code` is written between backquotes;
- the characters are ASCII.
"""

import re
from dataclasses import dataclass

import click

SPACES = re.compile(r"\s+")
BULLETS = ("- ", "* ")
BACKQUOTE = "`"


@dataclass(eq=False)
class BadComment(click.ClickException):
    """A documentation comment that is not in the subset of Markdown above."""

    where: str
    problem: str

    def __post_init__(self) -> None:
        super().__init__(f"{self.where}: documentation comment {self.problem}")


@dataclass(frozen=True, kw_only=True)
class Words:
    """Text, with its spaces collapsed."""

    text: str


@dataclass(frozen=True, kw_only=True)
class Code:
    """Program text: an identifier, a number, an expression."""

    text: str


type Span = Words | Code
type Spans = tuple[Span, ...]


@dataclass(frozen=True, kw_only=True)
class Paragraph:
    spans: Spans


@dataclass(frozen=True, kw_only=True)
class Bullets:
    items: tuple[Spans, ...]


type Block = Paragraph | Bullets


@dataclass(frozen=True, kw_only=True)
class Prose:
    blocks: tuple[Block, ...]


def parse_spans(text: str, *, where: str) -> Spans:
    parts = text.split(BACKQUOTE)
    if len(parts) % 2 == 0:
        raise BadComment(where, "has an unmatched backquote")

    spans = list[Span]()
    for index, part in enumerate(parts):
        normalized = SPACES.sub(" ", part)
        if index % 2 == 1:
            if not normalized.strip():
                raise BadComment(where, "has an empty code span")

            spans.append(Code(text=normalized.strip()))
        elif normalized:
            spans.append(Words(text=normalized))

    return tuple(spans)


def parse_chunk(lines: list[str], *, where: str) -> list[Block]:
    """The blocks of the lines of one chunk of a comment: a paragraph, then a list."""

    first_item = next((n for n, line in enumerate(lines) if line.startswith(BULLETS)), len(lines))
    blocks = list[Block]()
    if first_item:
        blocks.append(Paragraph(spans=parse_spans(" ".join(lines[:first_item]), where=where)))

    items = list[str]()
    for line in lines[first_item:]:
        if line.startswith(BULLETS):
            items.append(line[len(BULLETS[0]) :])
        else:
            items[-1] += " " + line

    if items:
        blocks.append(Bullets(items=tuple(parse_spans(item, where=where) for item in items)))

    return blocks


def parse_prose(comment: str, *, where: str) -> Prose:
    """The prose of the documentation comment `comment`, found at `where`."""

    if not comment.isascii():
        raise BadComment(where, "has characters other than ASCII")

    blocks = list[Block]()
    chunk = list[str]()
    for line in [*(line.strip() for line in comment.strip().splitlines()), ""]:
        if line:
            chunk.append(line)
        elif chunk:
            blocks.extend(parse_chunk(chunk, where=where))
            chunk = []

    if not blocks:
        raise BadComment(where, "is empty")

    return Prose(blocks=tuple(blocks))
