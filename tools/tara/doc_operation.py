"""Typed operations preserve bit widths and sequencing while rendering reference notation."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum, auto

import msgspec


class Rendering(StrEnum):
    EXACT = auto()
    CARD = auto()


@dataclass(frozen=True, kw_only=True)
class Printed:
    text: str
    precedence: int = 10

    def operand(self, precedence: int, *, right: bool = False) -> str:
        if self.precedence < precedence or (right and self.precedence == precedence):
            return f"({self.text})"

        return self.text


class Value(msgspec.Struct, frozen=True, tag="value", tag_field="kind"):
    text: str
    width: int | None

    def render(self, rendering: Rendering = Rendering.EXACT) -> Printed:
        if rendering == Rendering.CARD and self.text.startswith(("0x", "0b")):
            return Printed(text=str(int(self.text, 0)))

        return Printed(text={"bitzero": "0", "bitone": "1"}.get(self.text, self.text))

    @property
    def references(self) -> frozenset[str]:
        return frozenset()


class Call(msgspec.Struct, frozen=True, tag="call", tag_field="kind"):
    name: str
    arguments: tuple[Expression, ...]
    width: int | None
    notation: str | None

    @property
    def helper(self) -> str:
        match self.name:
            case "sail_sign_extend" | "sign_extend":
                return "sign_extend"
            case "sail_zero_extend" | "zero_extend":
                return "zero_extend"
            case "sail_shiftleft":
                return "shift_left"
            case "sail_shiftright":
                return "shift_right"
            case "vector_access" | "bitvector_access" | "plain_vector_access":
                return "index"
            case "vector_subrange" | "subrange_bits":
                return "slice"
            case "bitvector_concat":
                return "concat"
            case "get_slice_int":
                return (
                    "wrap"
                    if isinstance(self.arguments[2], Value) and self.arguments[2].text == "0"
                    else "integer_slice"
                )
            case "Retired" | "Stopped" | "Illegal":
                return "retirement"
            case "encdec_backwards_matches":
                return "encoding_match"
            case "bitvector_length":
                return "length"
            case _:
                return self.name

    def render(self, rendering: Rendering = Rendering.EXACT) -> Printed:
        arguments = [argument.render(rendering) for argument in self.arguments]
        text = [argument.text for argument in arguments]
        match self.helper:
            case "signed" | "unsigned":
                if rendering == Rendering.CARD:
                    return (
                        Printed(text=f"s({text[0]})") if self.helper == "signed" else arguments[0]
                    )

                width = self.arguments[0].width
                return Printed(text=f"{self.helper}{width if width is not None else ''}({text[0]})")
            case "sign_extend" | "zero_extend":
                operand = 1 if self.name in {"sign_extend", "zero_extend"} else 0
                width = self.width if self.width is not None else text[1 - operand]
                if rendering == Rendering.CARD:
                    name = "sext" if self.helper == "sign_extend" else "zext"
                    return Printed(text=f"{name}{width}({text[operand]})")

                return Printed(text=f"{self.helper}_{width}({text[operand]})")
            case "wrap":
                width = self.width if self.width is not None else text[0]
                if rendering == Rendering.CARD and self.width is not None and self.width > 0:
                    return Printed(text=f"{arguments[1].operand(10)}[{self.width - 1}:0]")

                return Printed(text=f"wrap{width}({text[1]})")
            case "length":
                return Printed(text=f"length({text[0]})")
            case "integer_slice":
                return Printed(text=f"integer_slice({text[1]}, {text[2]}, {text[0]})")
            case "shift_left" | "shift_right":
                operator = "<<" if self.helper == "shift_left" else ">>"
                return Printed(
                    text=f"{arguments[0].operand(5)} {operator} {arguments[1].operand(5, right=True)}",
                    precedence=5,
                )
            case "index":
                return Printed(text=f"{arguments[0].operand(10)}[{text[1]}]")
            case "slice":
                return Printed(text=f"{arguments[0].operand(10)}[{text[1]}:{text[2]}]")
            case "concat":
                if rendering == Rendering.CARD:
                    return Binary(
                        operator="++",
                        left=self.arguments[0],
                        right=self.arguments[1],
                        width=self.width,
                    ).render(rendering)

                return Printed(text=f"concat({', '.join(text)})")
            case "not_vec":
                return Printed(text=f"~{arguments[0].operand(8)}", precedence=8)
            case "retirement":
                return Printed(text=self.name if self.name != "Illegal" else f"Illegal({text[0]})")
            case _:
                pass

        if self.notation is not None:
            rendered = self.notation
            for index, argument in enumerate(arguments):
                # Parentheses matter in templates such as `{0}[7:0]` and `~{0}`.
                placeholder = f"{{{index}}}"
                position = rendered.find(placeholder)
                finish = position + len(placeholder)
                apart = position < 0 or (
                    (position == 0 or rendered[position - 1] in "[(, ")
                    and (finish == len(rendered) or rendered[finish] in "]), ")
                )
                replacement = argument.text if apart else argument.operand(10)
                rendered = rendered.replace(placeholder, replacement)

            if rendering == Rendering.EXACT:
                rendered = rendered.replace(" = ", " <- ")

            return Printed(text=rendered)

        return Printed(text=f"{self.name}({', '.join(text)})")

    @property
    def references(self) -> frozenset[str]:
        return frozenset({self.helper}).union(*(argument.references for argument in self.arguments))


class Binary(msgspec.Struct, frozen=True, tag="binary", tag_field="kind"):
    operator: str
    left: Expression
    right: Expression
    width: int | None

    def render(self, rendering: Rendering = Rendering.EXACT) -> Printed:
        left, right = self.left.render(rendering), self.right.render(rendering)
        if self.operator == "++":
            if rendering == Rendering.CARD:
                if isinstance(self.left, Value) and left.text == "0" and self.width is not None:
                    return Printed(text=f"zext{self.width}({right.text})")

                return Printed(
                    text=f"{left.operand(6)} ++ {right.operand(6, right=True)}", precedence=6
                )

            return Printed(text=f"concat({left.text}, {right.text})")

        precedence = {
            "*": 7,
            "/": 7,
            "%": 7,
            "+": 6,
            "-": 6,
            "<<": 5,
            ">>": 5,
            "<": 4,
            "<=": 4,
            ">": 4,
            ">=": 4,
            "==": 3,
            "!=": 3,
            "&": 2,
            "^": 1,
            "|": 0,
            "&&": -1,
            "||": -2,
        }[self.operator]
        text = f"{left.operand(precedence)} {self.operator} {right.operand(precedence, right=True)}"
        if (
            rendering == Rendering.EXACT
            and self.width is not None
            and self.operator in {"+", "-", "*"}
        ):
            return Printed(text=f"wrap{self.width}({text})")

        return Printed(text=text, precedence=precedence)

    @property
    def references(self) -> frozenset[str]:
        helpers = (
            {"concat"}
            if self.operator == "++"
            else (
                {"wrap"}
                if self.width is not None and self.operator in {"+", "-", "*"}
                else set[str]()
            )
        )
        return self.left.references | self.right.references | helpers


class Slice(msgspec.Struct, frozen=True, tag="slice", tag_field="kind"):
    value: Expression
    high: Expression
    low: Expression | None
    width: int | None

    def render(self, rendering: Rendering = Rendering.EXACT) -> Printed:
        index = self.high.render(rendering).text
        if self.low is not None:
            index += f":{self.low.render(rendering).text}"

        return Printed(text=f"{self.value.render(rendering).operand(10)}[{index}]")

    @property
    def references(self) -> frozenset[str]:
        return (
            self.value.references
            | self.high.references
            | (self.low.references if self.low is not None else frozenset[str]())
            | {"index" if self.low is None else "slice"}
        )


class Choice(msgspec.Struct, frozen=True, tag="choice", tag_field="kind"):
    condition: Expression
    yes: Expression
    no: Expression
    width: int | None

    def render(self, rendering: Rendering = Rendering.EXACT) -> Printed:
        condition = self.condition.render(rendering).text
        yes, no = self.yes.render(rendering).text, self.no.render(rendering).text
        if rendering == Rendering.CARD:
            return Printed(text=f"{condition} ? {yes} : {no}", precedence=-3)

        return Printed(
            text=f"if {condition} then {yes} else {no}",
            precedence=-3,
        )

    @property
    def references(self) -> frozenset[str]:
        return self.condition.references | self.yes.references | self.no.references


type Expression = Value | Call | Binary | Slice | Choice


class Evaluate(msgspec.Struct, frozen=True, tag="evaluate", tag_field="kind"):
    value: Expression

    def lines(self, indent: str = "", *, rendering: Rendering = Rendering.EXACT) -> list[str]:
        return [indent + self.value.render(rendering).text]

    @property
    def references(self) -> frozenset[str]:
        return self.value.references


class Assign(msgspec.Struct, frozen=True, tag="assign", tag_field="kind"):
    target: Expression
    value: Expression

    def lines(self, indent: str = "", *, rendering: Rendering = Rendering.EXACT) -> list[str]:
        assignment = "=" if rendering == Rendering.CARD else "<-"
        return [
            f"{indent}{self.target.render(rendering).text} {assignment} {self.value.render(rendering).text}"
        ]

    @property
    def references(self) -> frozenset[str]:
        return self.target.references | self.value.references


class Bind(msgspec.Struct, frozen=True, tag="bind", tag_field="kind"):
    name: str
    value: Expression
    body: tuple[Statement, ...]

    def lines(self, indent: str = "", *, rendering: Rendering = Rendering.EXACT) -> list[str]:
        binding = "" if rendering == Rendering.CARD else "let "
        return [
            f"{indent}{binding}{self.name} = {self.value.render(rendering).text}",
            *(
                line
                for statement in self.body
                for line in statement.lines(indent, rendering=rendering)
            ),
        ]

    @property
    def references(self) -> frozenset[str]:
        return self.value.references.union(*(statement.references for statement in self.body))


class Branch(msgspec.Struct, frozen=True, tag="branch", tag_field="kind"):
    condition: Expression
    yes: tuple[Statement, ...]
    no: tuple[Statement, ...]

    def lines(self, indent: str = "", *, rendering: Rendering = Rendering.EXACT) -> list[str]:
        if rendering == Rendering.CARD:
            yes = "; ".join(
                line for statement in self.yes for line in statement.lines(rendering=rendering)
            )
            text = f"{indent}if ({self.condition.render(rendering).text}) {{ {yes} }}"
            if self.no:
                no = "; ".join(
                    line for statement in self.no for line in statement.lines(rendering=rendering)
                )
                text += f" else {{ {no} }}"

            return [text]

        lines = [
            f"{indent}if {self.condition.render().text}:",
            *(line for statement in self.yes for line in statement.lines(indent + "  ")),
        ]
        if self.no:
            lines += [
                indent + "else:",
                *(line for statement in self.no for line in statement.lines(indent + "  ")),
            ]

        return lines

    @property
    def references(self) -> frozenset[str]:
        return self.condition.references.union(
            *(statement.references for statement in (*self.yes, *self.no))
        )


type Statement = Evaluate | Assign | Bind | Branch


@dataclass(frozen=True, kw_only=True)
class Operation:
    statements: tuple[Statement, ...]

    @property
    def lines(self) -> list[str]:
        return [line for statement in self.statements for line in statement.lines()]

    @property
    def card_lines(self) -> list[str]:
        return [
            line
            for statement in self.statements
            for line in statement.lines(rendering=Rendering.CARD)
        ] or ["—"]

    @property
    def card(self) -> str:
        return "\n".join(self.card_lines)

    @property
    def references(self) -> frozenset[str]:
        return frozenset[str]().union(*(statement.references for statement in self.statements))

    def __str__(self) -> str:
        return "\n".join(self.lines)
