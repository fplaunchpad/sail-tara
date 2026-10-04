"""Render instruction listings from normalized Sail metadata."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import click
import msgspec

from tara.doc_tables import Instruction, Metadata

type NonEmptyString = Annotated[str, msgspec.Meta(min_length=1)]


class AnchorDetails(msgspec.Struct, frozen=True, kw_only=True):
    comment: str


class Anchor(msgspec.Struct, frozen=True, kw_only=True):
    anchor: AnchorDetails


class Bundle(msgspec.Struct, frozen=True, kw_only=True):
    anchors: dict[NonEmptyString, Anchor]


class SectionsError(click.ClickException):
    """Instruction metadata references missing or undocumented source groups."""


def instruction_listing(instruction: Instruction) -> str:
    name = instruction.constructor
    if not name.isidentifier():
        raise SectionsError(f"invalid instruction constructor: {name}")

    selector = f"{name}({', '.join('_' for _ in range(instruction.operand_count))})"

    lines = [
        f"[#insn-{name}%breakable]",
        f"==== `{name}`",
        "",
        "[.instruction%unbreakable]",
        "--",
        "",
        f'include::sailcomment:execute[clause="{selector}",indent=0]',
        "",
        f'sail::encode[clause="{selector}"]',
        f"sail::decode[grep=Some\\({name}\\(]",
        f'sail::execute[clause="{selector}"]',
        f'sail::assembly[type=mapping,left-clause="{selector}"]',
        "",
        "--",
        "",
    ]
    return "\n".join(lines)


def render_sections(bundle: Bundle, metadata: Metadata) -> str:
    groups: dict[str, list[Instruction]] = {}
    for instruction in metadata.instructions:
        group = Path(instruction.source_file).stem
        if not group.isidentifier():
            raise SectionsError(f"invalid instruction source filename: {instruction.source_file}")

        groups.setdefault(group, []).append(instruction)

    sections: list[str] = []
    for group, instructions in groups.items():
        for anchor in (f"section_{group}", group):
            anchor_data = bundle.anchors.get(anchor)
            if anchor_data is None:
                raise SectionsError(f"native Sail bundle is missing instruction anchor {anchor}")
            if not anchor_data.anchor.comment.strip():
                raise SectionsError(f"native Sail anchor {anchor} has no comment")

            sections.append(f"include::sailcomment:{anchor}[type=anchor,indent=0]\n")

        sections.extend(instruction_listing(instruction) for instruction in instructions)

    return "\n".join(sections)


def write_sections(bundle_path: Path, metadata_path: Path, output_path: Path) -> None:
    try:
        bundle = msgspec.json.decode(bundle_path.read_bytes(), type=Bundle)
        metadata = msgspec.json.decode(metadata_path.read_bytes(), type=Metadata)
    except (OSError, msgspec.DecodeError, ValueError) as error:
        raise SectionsError(str(error)) from error

    rendered = render_sections(bundle, metadata)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(rendered, encoding="utf-8")


@click.command()
@click.option(
    "--bundle",
    required=True,
    type=click.Path(path_type=Path, exists=True, dir_okay=False, readable=True),
)
@click.option(
    "--metadata",
    required=True,
    type=click.Path(path_type=Path, exists=True, dir_okay=False, readable=True),
)
@click.option(
    "--out",
    "output_path",
    required=True,
    type=click.Path(path_type=Path, dir_okay=False),
)
def main(bundle: Path, metadata: Path, output_path: Path) -> None:
    """Render instruction listings from Sail metadata and anchors."""

    write_sections(bundle, metadata, output_path)


if __name__ == "__main__":
    main()
