"""A small typed AsciiDoc table model for generated documentation tables."""

from dataclasses import dataclass
from enum import StrEnum


class Alignment(StrEnum):
    """Column alignment in an AsciiDoc table."""

    DEFAULT = ""
    LEFT = "<"
    CENTERED = "^"
    RIGHT = ">"


class CellAlignment(StrEnum):
    """Cell-level alignment overrides."""

    DEFAULT = ""
    CENTERED = "^m"


@dataclass(frozen=True, kw_only=True)
class Column:
    width: int = 1
    repeat: int = 1
    alignment: Alignment = Alignment.DEFAULT

    def __post_init__(self) -> None:
        if type(self.width) is not int or self.width < 1:
            raise ValueError("column width must be a positive integer")
        if type(self.repeat) is not int or self.repeat < 1:
            raise ValueError("column repeat must be a positive integer")

    def to_asciidoc(self) -> str:
        specification = f"{self.alignment}{self.width}"
        return f"{self.repeat}*{specification}" if self.repeat > 1 else specification


@dataclass(frozen=True, kw_only=True)
class Text:
    value: str

    def to_asciidoc(self) -> str:
        return escape_cell_text(self.value)


@dataclass(frozen=True, kw_only=True)
class Code:
    value: str

    def to_asciidoc(self) -> str:
        return f"`+{escape_cell_text(self.value)}+`"


@dataclass(frozen=True, kw_only=True)
class Anchor:
    identifier: str

    def to_asciidoc(self) -> str:
        return f"[[{self.identifier}]]"


@dataclass(frozen=True, kw_only=True)
class Reference:
    target: str
    content: tuple[Inline, ...]

    def __post_init__(self) -> None:
        if not self.target:
            raise ValueError("reference target must not be empty")
        if not self.content:
            raise ValueError("reference content must not be empty")

    def to_asciidoc(self) -> str:
        content = "".join(item.to_asciidoc() for item in self.content)
        return f"<<{self.target},{content}>>"


type Inline = Text | Code | Anchor | Reference


@dataclass(frozen=True, kw_only=True)
class Cell:
    content: tuple[Inline, ...]
    colspan: int = 1
    alignment: CellAlignment = CellAlignment.DEFAULT

    def __post_init__(self) -> None:
        if not self.content:
            raise ValueError("table cells must not be empty")
        if type(self.colspan) is not int or self.colspan < 1:
            raise ValueError("cell colspan must be a positive integer")

    def to_asciidoc(self) -> str:
        attributes = f"{self.colspan}+" if self.colspan > 1 else ""
        attributes += self.alignment
        content = "".join(item.to_asciidoc() for item in self.content)
        return f"{attributes}|{content}"


@dataclass(frozen=True, kw_only=True)
class Row:
    cells: tuple[Cell, ...]

    def __post_init__(self) -> None:
        if not self.cells:
            raise ValueError("table rows must not be empty")

    def to_asciidoc(self) -> str:
        return " ".join(cell.to_asciidoc() for cell in self.cells)


@dataclass(frozen=True, kw_only=True)
class Table:
    columns: tuple[Column, ...]
    rows: tuple[Row, ...]
    header: bool = True

    def __post_init__(self) -> None:
        if not self.columns:
            raise ValueError("tables must have columns")
        if not self.rows:
            raise ValueError("tables must have rows")
        column_count = sum(column.repeat for column in self.columns)
        for row in self.rows:
            cell_count = sum(cell.colspan for cell in row.cells)
            if cell_count != column_count:
                raise ValueError(
                    f"row spans {cell_count} columns; table has {column_count} columns"
                )

    def to_asciidoc(self) -> str:
        columns = ",".join(column.to_asciidoc() for column in self.columns)
        options = ', options="header"' if self.header else ""
        rows = [f'[cols="{columns}"{options}]', "|==="]
        rows.extend(row.to_asciidoc() for row in self.rows)
        rows.append("|===")
        return "\n".join(rows) + "\n"


def escape_cell_text(value: str) -> str:
    """Escape a table separator in plain or passthrough cell content."""

    return value.replace("|", "\\|")
