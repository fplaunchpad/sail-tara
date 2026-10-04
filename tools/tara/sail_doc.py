"""The documentation bundle of Sail's doc backend, and the macros of its LaTeX backend, as typed
values.

`sail --doc --doc-embed plain --doc-embed-with-location --doc-bundle FILE MODEL.sail` writes a JSON
bundle: the definitions of the model and of Sail's library, each with its source text, and the
model's with the file, the line and the documentation comment (`/*! ... */`). The definitions of
Sail's library have no location and are left out here. `sail --latex --latex-prefix PREFIX` writes
`commands.tex`, which defines one macro per definition.
"""

import json
import re
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn

import click

# A JSON value: what `json.loads` returns.
type Json = bool | int | float | str | list[Json] | dict[str, Json] | None


@dataclass(eq=False)
class MalformedBundle(click.ClickException):
    """The bundle is not what Sail 0.20 writes: `where` names the value, `problem` what is wrong."""

    bundle: Path
    where: str
    problem: str

    def __post_init__(self) -> None:
        super().__init__(f"{self.bundle}: {self.where}: {self.problem}")


@dataclass(frozen=True, kw_only=True)
class Node:
    """A JSON value of the bundle, with its place in the bundle for diagnostics."""

    value: Json
    where: str
    bundle: Path

    def fail(self, problem: str) -> NoReturn:
        raise MalformedBundle(self.bundle, self.where, problem)

    def child(self, key: str, value: Json) -> Node:
        return Node(value=value, where=f"{self.where}.{key}", bundle=self.bundle)

    def mapping(self) -> dict[str, Node]:
        if not isinstance(self.value, dict):
            self.fail("expected an object")

        return {key: self.child(key, value) for key, value in self.value.items()}

    def sequence(self) -> list[Node]:
        if not isinstance(self.value, list):
            self.fail("expected an array")

        return [self.child(str(index), value) for index, value in enumerate(self.value)]

    def text(self) -> str:
        if not isinstance(self.value, str):
            self.fail("expected a string")

        return self.value

    def integer(self) -> int:
        if isinstance(self.value, bool) or not isinstance(self.value, int):
            self.fail("expected an integer")

        return self.value

    def field(self, key: str) -> Node:
        fields = self.mapping()
        if key not in fields:
            self.fail(f"has no field {key!r}")

        return fields[key]

    def optional_field(self, key: str) -> Node | None:
        return self.mapping().get(key)

    def is_text(self) -> bool:
        return isinstance(self.value, str)


@dataclass(frozen=True, kw_only=True)
class Source:
    """A piece of the model's source: its text and where it starts."""

    text: str
    file: Path
    line: int
    offset: int

    @property
    def position(self) -> tuple[int, int]:
        """Orders pieces of one file as they appear in it."""

        return (self.line, self.offset)

    @classmethod
    def parse(cls, node: Node) -> Source:
        # {"contents": TEXT, "file": PATH, "loc": [line, bol, offset, end line, end bol, end]}
        location = [item.integer() for item in node.field("loc").sequence()]
        if len(location) != 6:
            node.field("loc").fail("expected six numbers")

        return cls(
            text=node.field("contents").text(),
            file=Path(node.field("file").text()),
            line=location[0],
            offset=location[2],
        )


def parse_located(node: Node) -> Source | None:
    """The source in `node`, or None when it has no location (the library's definitions)."""

    return None if node.is_text() else Source.parse(node)


@dataclass(frozen=True, kw_only=True)
class App:
    """A constructor applied to patterns, such as `ADD(rd, rs1, rs2)`: its name."""

    name: str


@dataclass(frozen=True, kw_only=True)
class OtherPattern:
    """A pattern of another kind, such as the bits that `decode` matches."""

    kind: str


type Pattern = App | OtherPattern


def parse_pattern(node: Node) -> Pattern:
    match node.field("type").text():
        case "app":
            return App(name=node.field("id").text())
        case kind:
            return OtherPattern(kind=kind)


@dataclass(frozen=True, kw_only=True)
class Clause:
    """A clause of a function: the whole function when it has one, else one of a scattered
    function's. `number` is its place among them, from 0."""

    number: int
    source: Source
    pattern: Pattern
    body: Source
    comment: str | None


@dataclass(frozen=True, kw_only=True)
class Function:
    name: str
    clauses: tuple[Clause, ...]


@dataclass(frozen=True, kw_only=True)
class Val:
    """An explicit `val` declaration. A function with its signature inline has none here."""

    name: str
    source: Source
    comment: str | None


@dataclass(frozen=True, kw_only=True)
class TypeDefinition:
    """A type. Sail drops the documentation comment of a type, so it has none."""

    name: str
    source: Source


@dataclass(frozen=True, kw_only=True)
class Register:
    name: str
    source: Source
    comment: str | None


@dataclass(frozen=True, kw_only=True)
class Let:
    name: str
    source: Source
    comment: str | None


@dataclass(frozen=True, kw_only=True)
class Anchor:
    """A `$anchor NAME` pragma: documentation that belongs to no definition."""

    name: str
    source: Source
    comment: str | None


@dataclass(frozen=True, kw_only=True)
class Bundle:
    """The definitions of the model, by name."""

    types: Mapping[str, TypeDefinition]
    registers: Mapping[str, Register]
    lets: Mapping[str, Let]
    vals: Mapping[str, Val]
    functions: Mapping[str, Function]
    anchors: Mapping[str, Anchor]

    @property
    def is_empty(self) -> bool:
        """Whether the bundle has no definition of the model, as when it has no locations."""

        definitions = (self.types, self.registers, self.lets, self.vals, self.functions)
        return not any(definitions) and not self.anchors


@dataclass(eq=False)
class MissingLocations(click.ClickException):
    """The bundle has no locations: Sail writes them for a model named by a relative path."""

    bundle: Path

    def __post_init__(self) -> None:
        super().__init__(
            f"{self.bundle}: the definitions of the model have no locations; write the bundle "
            "with sail --doc --doc-embed plain --doc-embed-with-location, naming the model by "
            "a path from the working directory"
        )


def parse_comment(node: Node) -> str | None:
    comment = node.optional_field("comment")
    return None if comment is None else comment.text()


def parse_clause(node: Node) -> Clause | None:
    source = parse_located(node.field("source"))
    if source is None:
        return None

    return Clause(
        number=node.field("number").integer(),
        source=source,
        pattern=parse_pattern(node.field("pattern")),
        body=Source.parse(node.field("body")),
        comment=parse_comment(node),
    )


def parse_function(name: str, node: Node) -> Function | None:
    # One clause is an object; the clauses of a scattered function are an array of them.
    body = node.field("function")
    nodes = body.sequence() if isinstance(body.value, list) else [body]
    clauses = tuple(clause for item in nodes if (clause := parse_clause(item)) is not None)
    if [clause.number for clause in clauses] not in ([], list(range(len(clauses)))):
        body.fail("has clauses that are not numbered in order from 0")

    return Function(name=name, clauses=clauses) if clauses else None


def parse_types(section: Node) -> dict[str, TypeDefinition]:
    types = dict[str, TypeDefinition]()
    for name, node in section.mapping().items():
        if (source := parse_located(node.field("type"))) is not None:
            types[name] = TypeDefinition(name=name, source=source)

    return types


def parse_registers(section: Node) -> dict[str, Register]:
    registers = dict[str, Register]()
    for name, node in section.mapping().items():
        body = node.field("register")
        if (source := parse_located(body.field("source"))) is not None:
            registers[name] = Register(name=name, source=source, comment=parse_comment(body))

    return registers


def parse_lets(section: Node) -> dict[str, Let]:
    lets = dict[str, Let]()
    for name, node in section.mapping().items():
        body = node.field("let")
        if (source := parse_located(body.field("source"))) is not None:
            lets[name] = Let(name=name, source=source, comment=parse_comment(body))

    return lets


def parse_vals(section: Node) -> dict[str, Val]:
    vals = dict[str, Val]()
    for name, node in section.mapping().items():
        body = node.field("val")
        if (source := parse_located(body.field("source"))) is not None:
            vals[name] = Val(name=name, source=source, comment=parse_comment(body))

    return vals


def parse_functions(section: Node) -> dict[str, Function]:
    functions = dict[str, Function]()
    for name, node in section.mapping().items():
        if (function := parse_function(name, node)) is not None:
            functions[name] = function

    return functions


def parse_anchors(section: Node) -> dict[str, Anchor]:
    anchors = dict[str, Anchor]()
    for name, node in section.mapping().items():
        body = node.field("anchor")
        if (source := parse_located(body.field("source"))) is None:
            raise MissingLocations(node.bundle)

        anchors[name] = Anchor(name=name, source=source, comment=parse_comment(body))

    return anchors


def parse_bundle(path: Path) -> Bundle:
    """The definitions of the model in the bundle `path`."""

    root = Node(value=json.loads(path.read_text(encoding="utf-8")), where="bundle", bundle=path)
    bundle = Bundle(
        types=parse_types(root.field("types")),
        registers=parse_registers(root.field("registers")),
        lets=parse_lets(root.field("lets")),
        vals=parse_vals(root.field("vals")),
        functions=parse_functions(root.field("functions")),
        anchors=parse_anchors(root.field("anchors")),
    )
    if bundle.is_empty:
        raise MissingLocations(path)

    return bundle


@dataclass(eq=False)
class MissingMacro(click.ClickException):
    """`commands.tex` has no macro for a definition of the bundle."""

    commands: Path
    what: str

    def __post_init__(self) -> None:
        super().__init__(f"{self.commands}: no macro for {self.what}")


# \newcommand{\taravalstep}{\saildoclabelled{tarazstep}{\saildocval{...}{\lstinputlisting[...]{FILE}}}}
MACRO = re.compile(
    r"\\newcommand\{\\(?P<macro>[A-Za-z]+)\}\{\\saildoclabelled\{(?P<label>[^}]*)\}"
    r".*?\\lstinputlisting\[language=sail\]\{(?P<listing>[^}]*)\}",
    re.S,
)
# \ifstrequal{#1}{read_byte}{\tarafnreadByte}{}%
ENTRY = re.compile(r"\\ifstrequal\{#1\}\{(?P<name>[^}\\]*)\}\{\\(?P<macro>[A-Za-z]+)\}")
# Sail marks the calls in a listing as #\hyperref[LABEL]{TEXT}#, and escapes underscores.
LINK = re.compile(r"#\\hyperref\[[^\]]*\]\{(?P<text>[^}]*)\}#")
IDENTIFIER = re.compile(r"[A-Za-z0-9_]+")
CATEGORIES = ("val", "fn", "type", "let", "register", "outcome")


@dataclass(frozen=True, kw_only=True)
class Macros:
    """The macros of `commands.tex` that typeset the definitions of the model.

    With the prefix `tara`, Sail names the macro of the function read_byte `\\tarafnreadByte` and
    lists the macros of values, functions, types, lets and registers by their names in `\\taraval`,
    `\\tarafn`, `\\taratype`, `\\taralet` and `\\tararegister`: those tables find them. The
    macros of the clauses of a scattered function are named from the constructors in their
    patterns, which the bundle does not repeat: they are found by their labels, which end with the
    name of the function, and by their order, which is the order of the clauses.
    """

    commands: Path
    prefix: str
    named: Mapping[tuple[str, str], str]
    clause_labels: tuple[tuple[str, str], ...]
    listings: Mapping[str, Path]

    @classmethod
    def parse(cls, commands: Path, *, prefix: str) -> Macros:
        text = commands.read_text(encoding="utf-8")

        named = dict[tuple[str, str], str]()
        for entry in ENTRY.finditer(text):
            for category in CATEGORIES:
                if entry["macro"].startswith(prefix + category):
                    named[(category, entry["name"])] = entry["macro"]

        clause_labels = list[tuple[str, str]]()
        listings = dict[str, Path]()
        for match in MACRO.finditer(text):
            # The listings are next to commands.tex, whichever way their paths are written there.
            listings[match["macro"]] = commands.parent / Path(match["listing"]).name
            if match["macro"].startswith(f"{prefix}fcl"):
                clause_labels.append((match["macro"], match["label"]))

        return cls(
            commands=commands,
            prefix=prefix,
            named=named,
            clause_labels=tuple(clause_labels),
            listings=listings,
        )

    def named_macro(self, category: str, name: str) -> str:
        """The macro of the value, function, type, let or register `name`."""

        try:
            return self.named[(category, name)]
        except KeyError:
            raise MissingMacro(self.commands, f"{category} {name}") from None

    def clause_macro(self, function: str, number: int) -> str:
        """The macro of clause `number` of the scattered function `function`."""

        if not IDENTIFIER.fullmatch(function):
            raise MissingMacro(self.commands, f"the clauses of {function}")

        # Sail's label of a clause is the prefix, `fcl` and the clause's name, then the function's
        # name with a z in front, and each z and underscore in it written as zz and zy.
        suffix = "z" + function.replace("z", "zz").replace("_", "zy")
        macros = [macro for macro, label in self.clause_labels if label.endswith(suffix)]
        if number >= len(macros):
            raise MissingMacro(self.commands, f"clause {number} of {function}")

        return macros[number]

    def listing_text(self, macro: str) -> str:
        """The text that `macro` typesets, as source text with its spaces and breaks as they are."""

        text = self.listings[macro].read_text(encoding="utf-8")
        return LINK.sub(lambda link: link["text"], text).replace("\\_", "_")
