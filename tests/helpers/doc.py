"""The specification built apart from the repository, and what its HTML shows."""

import os
import shutil
import subprocess
from collections.abc import Iterator
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Self, override

import msgspec

ROOT = Path(__file__).parents[2]
INSTRUCTION_SETS = ROOT / "tests" / "instruction_sets"
# What the documentation recipes read.
SOURCES = ("justfile", "just", "model", "doc", "tools/tara", ".prettierrc.json")
ENTRY_POINT = "model/syntax.sail"
VOID_ELEMENTS = frozenset(
    {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "wbr"}
)


@dataclass(frozen=True)
class Workspace:
    """A copy of the model, the documentation sources and the recipes, in which `just doc`
    builds into build/doc without touching the repository."""

    root: Path

    @classmethod
    def copy(cls, root: Path) -> Self:
        for source in SOURCES:
            origin, copy = ROOT / source, root / source
            copy.parent.mkdir(parents=True, exist_ok=True)
            if origin.is_dir():
                shutil.copytree(origin, copy, ignore=shutil.ignore_patterns("__pycache__"))
            else:
                shutil.copy2(origin, copy)

        return cls(root)

    @property
    def output(self) -> Path:
        return self.root / "build" / "doc"

    def install(self, instruction_set: Path) -> None:
        """Make `instruction_set` the model the documentation recipes read."""

        shutil.copy2(instruction_set, self.root / ENTRY_POINT)

    def edit(self, path: str, old: str, new: str) -> None:
        """Replace the one occurrence of `old` in the file at `path`."""

        file = self.root / path
        text = file.read_text()
        if text.count(old) != 1:
            raise AssertionError(f"{path}: {old!r} occurs {text.count(old)} times")

        file.write_text(text.replace(old, new))

    def just(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["just", *arguments],
            cwd=self.root,
            env={**os.environ, "TARA_BUILD": str(self.root / "build")},
            capture_output=True,
            text=True,
            check=False,
        )

    def build(self, *arguments: str) -> None:
        """Run `just` with `arguments`, which must succeed."""

        run = self.just(*arguments)
        if run.returncode != 0:
            raise AssertionError(f"just {' '.join(arguments)} failed:\n{run.stdout}{run.stderr}")


class FunctionClause(msgspec.Struct, kw_only=True):
    source: str
    pattern: dict[str, object] | None = None
    body: str | None = None

    def matches(self, constructor: str) -> bool:
        """Whether the clause takes `constructor` apart."""

        return self.pattern is not None and self.pattern.get("id") == constructor

    def builds(self, constructor: str) -> bool:
        """Whether the clause returns `Some(constructor(...))`, as a decode clause does."""

        return (self.body or "").startswith(f"Some({constructor}(")


class Function(msgspec.Struct):
    function: list[FunctionClause]


class MappingClause(msgspec.Struct):
    source: str
    left: dict[str, object]

    def matches(self, constructor: str) -> bool:
        return self.left.get("id") == constructor


class Mapping(msgspec.Struct):
    mapping: list[MappingClause]


class Functions(msgspec.Struct):
    encode: Function
    decode: Function
    execute: Function


class Mappings(msgspec.Struct):
    assembly: Mapping


class Bundle(msgspec.Struct):
    """Sail's documentation bundle: the source of every clause, which the specification shows."""

    functions: Functions
    mappings: Mappings

    @classmethod
    def read(cls, path: Path) -> Self:
        return msgspec.json.decode(path.read_bytes(), type=cls)

    def clauses(self, constructor: str) -> list[str]:
        """The encode, decode, execute and assembly clauses of `constructor`, normalized."""

        functions = self.functions
        encode = [c.source for c in functions.encode.function if c.matches(constructor)]
        decode = [c.source for c in functions.decode.function if c.builds(constructor)]
        execute = [c.source for c in functions.execute.function if c.matches(constructor)]
        assembly = [c.source for c in self.mappings.assembly.mapping if c.matches(constructor)]
        return [normalize(source) for source in (*encode, *decode, *execute, *assembly)]


@dataclass(eq=False, kw_only=True)
class Element:
    """An HTML element; `children` holds its elements and text in document order."""

    tag: str
    attributes: dict[str, str | None]
    children: list[Element | str] = field(default_factory=list["Element | str"])

    @classmethod
    def parse(cls, html: str) -> Element:
        builder = TreeBuilder()
        builder.feed(html)
        builder.close()
        return builder.document

    @property
    def text(self) -> str:
        return "".join(child if isinstance(child, str) else child.text for child in self.children)

    def elements(self) -> Iterator[Element]:
        """This element and every element inside it, in document order."""

        yield self
        for child in self.children:
            if isinstance(child, Element):
                yield from child.elements()


class TreeBuilder(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.document = Element(tag="", attributes={})
        self.open = [self.document]

    @override
    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        element = Element(tag=tag, attributes=dict(attrs))
        self.open[-1].children.append(element)
        if tag not in VOID_ELEMENTS:
            self.open.append(element)

    @override
    def handle_endtag(self, tag: str) -> None:
        # Close the innermost open element with this tag, and any left open inside it.
        for depth in reversed(range(1, len(self.open))):
            if self.open[depth].tag == tag:
                del self.open[depth:]
                return

    @override
    def handle_data(self, data: str) -> None:
        self.open[-1].children.append(data)


@dataclass(frozen=True)
class Specification:
    """The rendered specification, with its text normalized as `normalize` does."""

    document: Element

    @classmethod
    def read(cls, path: Path) -> Self:
        return cls(Element.parse(path.read_text()))

    @property
    def text(self) -> str:
        return normalize(self.document.text)

    def listings(self, anchor: str) -> list[str]:
        """The code listings in the section whose heading has the id `anchor`."""

        for element in self.document.elements():
            headings = (child for child in element.children if isinstance(child, Element))
            if any(heading.attributes.get("id") == anchor for heading in headings):
                return [normalize(pre.text) for pre in element.elements() if pre.tag == "pre"]

        return []

    def table(self, header: str) -> list[list[str]]:
        """The rows of cell texts of the table whose first header cell reads `header`."""

        for table in self.document.elements():
            rows = [
                [normalize(cell.text) for cell in row.elements() if cell.tag in {"th", "td"}]
                for row in table.elements()
                if row.tag == "tr"
            ]
            if table.tag == "table" and rows and rows[0][0] == header:
                return rows

        raise LookupError(f"no table headed {header!r}")


def normalize(text: str) -> str:
    """`text` with its whitespace runs collapsed to single spaces."""

    return " ".join(text.split())
