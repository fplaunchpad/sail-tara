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
    """Cell horizontal and vertical alignment."""

    MIDDLE = ".^"
    CENTERED = "^.^"


class TableAlignment(StrEnum):
    """Horizontal alignment of a table on the page."""

    DEFAULT = ""
    CENTER = "center"
    LEFT = "left"
    RIGHT = "right"


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
    rowspan: int = 1
    alignment: CellAlignment = CellAlignment.MIDDLE

    def __post_init__(self) -> None:
        if not self.content:
            raise ValueError("table cells must not be empty")
        if type(self.colspan) is not int or self.colspan < 1:
            raise ValueError("cell colspan must be a positive integer")
        if type(self.rowspan) is not int or self.rowspan < 1:
            raise ValueError("cell rowspan must be a positive integer")

    def to_asciidoc(self) -> str:
        if self.colspan > 1 and self.rowspan > 1:
            attributes = f"{self.colspan}.{self.rowspan}+"
        elif self.colspan > 1:
            attributes = f"{self.colspan}+"
        elif self.rowspan > 1:
            attributes = f".{self.rowspan}+"
        else:
            attributes = ""
        attributes += self.alignment
        content = "".join(item.to_asciidoc() for item in self.content)
        return f"{attributes}|{content}"


@dataclass(frozen=True, kw_only=True)
class Row:
    cells: tuple[Cell, ...]

    def to_asciidoc(self) -> str:
        return " ".join(cell.to_asciidoc() for cell in self.cells)


@dataclass(frozen=True, kw_only=True)
class TableAttributes:
    header: bool = True
    width: int = 100
    alignment: TableAlignment = TableAlignment.DEFAULT

    def __post_init__(self) -> None:
        if type(self.header) is not bool:
            raise ValueError("table header must be a boolean")
        if type(self.width) is not int or not 1 <= self.width <= 100:
            raise ValueError("table width must be an integer from 1 to 100")

    def to_asciidoc(self) -> str:
        values: list[str] = []
        if self.header:
            values.append('options="header"')
        if self.width != 100:
            values.append(f'width="{self.width}%"')
        if self.alignment != TableAlignment.DEFAULT:
            values.append(f'role="{self.alignment}"')
        return f", {','.join(values)}" if values else ""


@dataclass(frozen=True, kw_only=True)
class Table:
    columns: tuple[Column, ...]
    rows: tuple[Row, ...]
    attributes: TableAttributes = TableAttributes()

    def __post_init__(self) -> None:
        if not self.columns:
            raise ValueError("tables must have columns")
        if not self.rows:
            raise ValueError("tables must have rows")
        column_count = sum(column.repeat for column in self.columns)
        occupied_until = [0] * column_count
        for row_index, row in enumerate(self.rows):
            occupied = [end_row > row_index for end_row in occupied_until]
            for cell in row.cells:
                try:
                    start_column = occupied.index(False)
                except ValueError as error:
                    raise ValueError(
                        f"row {row_index + 1} has more cells than the table's {column_count} columns"
                    ) from error

                end_column = start_column + cell.colspan
                if end_column > column_count:
                    raise ValueError(
                        f"row {row_index + 1} cell spans beyond the table's {column_count} columns"
                    )
                if any(occupied[start_column:end_column]):
                    raise ValueError(f"row {row_index + 1} cell overlaps a preceding row span")

                for column in range(start_column, end_column):
                    occupied[column] = True
                    occupied_until[column] = row_index + cell.rowspan

            if not all(occupied):
                covered_columns = sum(occupied)
                raise ValueError(
                    f"row {row_index + 1} covers {covered_columns} of {column_count} columns"
                )

        if any(end_row > len(self.rows) for end_row in occupied_until):
            raise ValueError("cell rowspan extends beyond the table's final row")

    def merge_adjacent_equal_cells(self) -> Table:
        """Merge identical cells that occupy the same columns in adjacent rows."""

        occupied_until = [0] * sum(column.repeat for column in self.columns)
        positions: dict[tuple[int, int], tuple[int, int]] = {}
        for row_index, row in enumerate(self.rows):
            occupied = [end_row > row_index for end_row in occupied_until]
            for cell_index, cell in enumerate(row.cells):
                start_column = occupied.index(False)
                end_column = start_column + cell.colspan
                positions[row_index, cell_index] = (start_column, end_column)
                for column in range(start_column, end_column):
                    occupied[column] = True
                    occupied_until[column] = row_index + cell.rowspan

        merged: dict[tuple[int, int], Cell] = {}
        removed: set[tuple[int, int]] = set()
        first_merge_row = 1 if self.attributes.header else 0
        for row_index in range(first_merge_row, len(self.rows)):
            row = self.rows[row_index]
            for cell_index, cell in enumerate(row.cells):
                location = (row_index, cell_index)
                if location in removed:
                    continue

                start_column, end_column = positions[location]
                merged_rowspan = cell.rowspan
                next_row = row_index + merged_rowspan
                while next_row < len(self.rows):
                    next_cell_index = next(
                        (
                            candidate_index
                            for candidate_index, candidate in enumerate(self.rows[next_row].cells)
                            if positions[next_row, candidate_index] == (start_column, end_column)
                            and candidate.content == cell.content
                            and candidate.alignment == cell.alignment
                        ),
                        None,
                    )
                    if next_cell_index is None:
                        break

                    next_cell = self.rows[next_row].cells[next_cell_index]
                    removed.add((next_row, next_cell_index))
                    merged_rowspan += next_cell.rowspan
                    next_row += next_cell.rowspan

                if merged_rowspan > cell.rowspan:
                    merged[location] = Cell(
                        content=cell.content,
                        colspan=cell.colspan,
                        rowspan=merged_rowspan,
                        alignment=cell.alignment,
                    )

        rows = tuple(
            Row(
                cells=tuple(
                    merged.get((row_index, cell_index), cell)
                    for cell_index, cell in enumerate(row.cells)
                    if (row_index, cell_index) not in removed
                )
            )
            for row_index, row in enumerate(self.rows)
        )
        return Table(columns=self.columns, rows=rows, attributes=self.attributes)

    def to_asciidoc(self) -> str:
        columns = ",".join(column.to_asciidoc() for column in self.columns)
        rows = [f'[cols="{columns}"{self.attributes.to_asciidoc()}]', "|==="]
        rows.extend(row.to_asciidoc() for row in self.rows)
        rows.append("|===")
        return "\n".join(rows) + "\n"


def escape_cell_text(value: str) -> str:
    """Escape a table separator in plain or passthrough cell content."""

    return value.replace("|", "\\|")
