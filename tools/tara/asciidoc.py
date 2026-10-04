"""AsciiDoc tables as typed values: `str()` of a table is its AsciiDoc source."""

from dataclasses import dataclass, replace
from enum import StrEnum

SEPARATOR = "|"
BACKGROUND = "cellbgcolor"  # the document attribute both converters read for a cell's background


class Alignment(StrEnum):
    """A column's horizontal alignment, as its specifier spells it."""

    LEFT = "<"
    CENTER = "^"


class CellAlignment(StrEnum):
    """A cell's alignment, as its specifier spells it; contents are always centred vertically."""

    COLUMN = ".^"  # horizontally as the column says
    CENTER = "^.^"


def escape(text: str) -> str:
    """`text` with the cell separator escaped."""

    return text.replace(SEPARATOR, f"\\{SEPARATOR}")


@dataclass(frozen=True)
class Text:
    text: str

    def __str__(self) -> str:
        return escape(self.text)


@dataclass(frozen=True)
class Code:
    """Monospace text, passed through without substitutions."""

    text: str

    def __str__(self) -> str:
        if "+" not in self.text:
            return f"`+{escape(self.text)}+`"

        # A plus would end the `+...+` passthrough, so the pass macro carries the text instead.
        return f"`pass:c[{escape(self.text).replace(']', '\\]')}]`"


@dataclass(frozen=True)
class Anchor:
    identifier: str

    def __str__(self) -> str:
        return f"[[{self.identifier}]]"


@dataclass(frozen=True, kw_only=True)
class Link:
    """A cross reference to the anchor `target`, shown as `content`."""

    target: str
    content: Text | Code

    def __str__(self) -> str:
        return f"<<{self.target},{self.content}>>"


@dataclass(frozen=True)
class Background:
    """Sets the background of this cell and the cells after it, or with no colour, clears it."""

    color: str | None

    def __str__(self) -> str:
        return f"{{set:{BACKGROUND}:{self.color}}}" if self.color else f"{{set:{BACKGROUND}!}}"


@dataclass(frozen=True)
class LineBreak:
    """A hard line break inside a cell."""

    def __str__(self) -> str:
        return " +\n"


type Inline = Text | Code | Anchor | Link | Background | LineBreak


@dataclass(frozen=True, kw_only=True)
class Cell:
    """A cell spanning `columns` columns and `rows` rows."""

    content: tuple[Inline, ...]
    columns: int = 1
    rows: int = 1
    alignment: CellAlignment = CellAlignment.COLUMN

    def __str__(self) -> str:
        columns = str(self.columns) if self.columns > 1 else ""
        rows = f".{self.rows}" if self.rows > 1 else ""
        span = f"{columns}{rows}+" if columns or rows else ""
        return f"{span}{self.alignment}{SEPARATOR}{''.join(map(str, self.content))}"


@dataclass(frozen=True, kw_only=True)
class Row:
    """A row of cells, on `background` (a colour such as `#F6DADF`) if given."""

    cells: tuple[Cell, ...]
    background: str | None = None


@dataclass(frozen=True, kw_only=True)
class Column:
    """`repeat` columns of relative width `width`."""

    width: int
    alignment: Alignment | None = None
    repeat: int = 1

    def __str__(self) -> str:
        specifier = f"{self.alignment or ''}{self.width}"
        return f"{self.repeat}*{specifier}" if self.repeat > 1 else specifier


@dataclass(frozen=True, kw_only=True)
class Table:
    """A centred table under a row of `header` labels, `width` percent of the page wide."""

    columns: tuple[Column, ...]
    header: tuple[str, ...]
    rows: tuple[Row, ...]
    width: int

    def __str__(self) -> str:
        columns = ",".join(map(str, self.columns))
        header = Row(
            cells=tuple(
                Cell(content=(Text(label),), alignment=CellAlignment.CENTER)
                for label in self.header
            )
        )
        lines = [
            f'[cols="{columns}", options="header",width="{self.width}%",role="center"]',
            "|===",
        ]
        background = None
        for row in (header, *self.rows):
            cells = row.cells
            if row.background != background:
                # The background is a document attribute, which a cell sets as it is converted:
                # set it in the first cell of a row, and clear it in the first cell after.
                first, *others = cells
                cells = (
                    replace(first, content=(Background(row.background), *first.content)),
                    *others,
                )
                background = row.background

            lines.append(" ".join(map(str, cells)))

        lines.append("|===")
        if background:
            lines.append(f":{BACKGROUND}!:")

        return "".join(f"{line}\n" for line in lines)
