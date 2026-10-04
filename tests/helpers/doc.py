"""Inspect generated documentation HTML without imposing its formatting."""

from html.parser import HTMLParser
from pathlib import Path

import msgspec


class FunctionClause(msgspec.Struct, kw_only=True):
    source: str
    pattern: dict[str, object] | None = None
    body: str | None = None
    comment: str | None = None


class Function(msgspec.Struct, kw_only=True):
    function: list[FunctionClause]


class MappingClause(msgspec.Struct, kw_only=True):
    source: str
    left: dict[str, object]


class Mapping(msgspec.Struct, kw_only=True):
    mapping: list[MappingClause]


class Functions(msgspec.Struct, kw_only=True):
    encode: Function
    decode: Function
    execute: Function


class Mappings(msgspec.Struct, kw_only=True):
    assembly_syntax: Mapping


class SourceBundle(msgspec.Struct, kw_only=True):
    functions: Functions
    mappings: Mappings


class InstructionListings(HTMLParser):
    """Collect instruction source blocks, prose, and table cells from rendered HTML."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.current: str | None = None
        self.in_pre = False
        self.source: list[str] | None = None
        self.listings: dict[str, list[str]] = {}
        self.text: list[str] = []
        self.table: list[list[str]] | None = None
        self.row: list[str] | None = None
        self.cell: list[str] | None = None
        self.cell_span = 1
        self.row_spans: list[int] | None = None
        self.tables: list[list[list[str]]] = []
        self.table_spans: list[list[list[int]]] = []
        self.current_table_spans: list[list[int]] | None = None
        self.stylesheets: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            identifier = attributes.get("id")
            self.current = (
                identifier.removeprefix("insn-")
                if identifier and identifier.startswith("insn-")
                else None
            )
        elif tag == "pre":
            self.in_pre = True
        elif tag == "code" and self.in_pre and self.current is not None:
            self.source = []
        elif tag == "link" and attributes.get("rel") == "stylesheet":
            href = attributes.get("href")
            if href is not None:
                self.stylesheets.append(href)
        elif tag == "table":
            self.table = []
            self.current_table_spans = []
        elif tag == "tr" and self.table is not None:
            self.row = []
            self.row_spans = []
        elif tag in {"th", "td"} and self.row is not None:
            self.cell = []
            colspan = attributes.get("colspan")
            self.cell_span = int(colspan) if colspan is not None else 1

    def handle_data(self, data: str) -> None:
        self.text.append(data)
        if self.source is not None:
            self.source.append(data)
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "code" and self.source is not None:
            if self.current is not None:
                self.listings.setdefault(self.current, []).append("".join(self.source))
            self.source = None
        elif tag == "pre":
            self.in_pre = False
        elif tag in {"th", "td"} and self.cell is not None and self.row is not None:
            self.row.append("".join(self.cell))
            if self.row_spans is not None:
                self.row_spans.append(self.cell_span)
            self.cell = None
        elif (
            tag == "tr"
            and self.table is not None
            and self.row is not None
            and self.row_spans is not None
            and self.current_table_spans is not None
        ):
            self.table.append(self.row)
            self.current_table_spans.append(self.row_spans)
            self.row = None
            self.row_spans = None
        elif tag == "table" and self.table is not None and self.current_table_spans is not None:
            self.tables.append(self.table)
            self.table_spans.append(self.current_table_spans)
            self.table = None
            self.current_table_spans = None


def normalize_document_text(text: str) -> str:
    """Normalize whitespace and inline code/emphasis delimiters for HTML comparisons."""

    text = text.replace("\\n", " ").replace("\\t", " ")
    return " ".join(text.replace("`", "").replace("*", "").split())


def read_instruction_sources(bundle_path: Path) -> dict[str, tuple[tuple[str, str, str, str], str]]:
    """Read native function and mapping sources, plus every instruction comment."""

    bundle = msgspec.json.decode(bundle_path.read_bytes(), type=SourceBundle)

    def function_sources(function: Function, *, decode: bool = False) -> dict[str, str]:
        sources: dict[str, str] = {}
        for clause in function.function:
            if decode:
                body = (clause.body or "").strip()
                constructor, separator, _arguments = body.removeprefix("Some(").partition("(")
                mnemonic = (
                    constructor
                    if body.startswith("Some(") and separator and constructor in expected_mnemonics
                    else None
                )
            else:
                pattern = clause.pattern
                value = pattern.get("id") if pattern is not None else None
                mnemonic = value if isinstance(value, str) else None
            if mnemonic is not None:
                if mnemonic in sources:
                    raise AssertionError(f"duplicate {mnemonic} source clause")
                sources[mnemonic] = clause.source
        return sources

    expected_mnemonics = tuple(
        constructor
        for clause in bundle.functions.encode.function
        if (pattern := clause.pattern) is not None
        if isinstance((constructor := pattern.get("id")), str)
    )
    if len(expected_mnemonics) != len(set(expected_mnemonics)):
        raise AssertionError("encode clauses contain duplicate instruction constructors")

    encode = function_sources(bundle.functions.encode)
    decode = function_sources(bundle.functions.decode, decode=True)
    execute = function_sources(bundle.functions.execute)
    assembly: dict[str, str] = {}
    for clause in bundle.mappings.assembly_syntax.mapping:
        value = clause.left.get("id")
        if isinstance(value, str):
            if value in assembly:
                raise AssertionError(f"duplicate {value} assembly mapping")
            assembly[value] = clause.source

    comments = {
        value: clause.comment
        for clause in bundle.functions.execute.function
        if clause.comment and clause.pattern is not None
        if isinstance((value := clause.pattern.get("id")), str)
    }
    sources: dict[str, tuple[tuple[str, str, str, str], str]] = {}
    for mnemonic in expected_mnemonics:
        selected = (encode, decode, execute, assembly)
        if any(mnemonic not in mapping for mapping in selected):
            raise AssertionError(f"{mnemonic} is missing a native source clause")
        comment = comments.get(mnemonic)
        if comment is None:
            raise AssertionError(f"{mnemonic} has no native instruction comment")
        sources[mnemonic] = (
            (encode[mnemonic], decode[mnemonic], execute[mnemonic], assembly[mnemonic]),
            comment,
        )

    if set(sources) != set(expected_mnemonics):
        raise AssertionError("instruction source sets differ")
    return sources
