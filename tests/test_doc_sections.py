from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import msgspec
import pytest

from helpers.doc import InstructionListings, normalize_document_text, read_instruction_sources
from tara.doc_sections import (
    Anchor,
    AnchorDetails,
    Bundle,
    SectionsError,
    render_sections,
)
from tara.doc_tables import Field, Instruction, Metadata, render_tables

ROOT = Path(__file__).parents[1]
MODEL = ROOT / "model"
TEMPLATE = ROOT / "doc/tara.adoc"
SECTIONS_LAYOUT = ROOT / "doc/sections.rb"


def instruction_metadata(
    *, constructor: str, source_file: str, opcode: str, operand_count: int
) -> Instruction:
    return Instruction(
        constructor=constructor,
        opcode_bits=opcode,
        syntax=f"{constructor}(...)",
        source_file=source_file,
        operand_count=operand_count,
        fields=[Field(name="opcode", width=5), Field(name="padding", width=11)],
    )


def native_bundle(instructions: list[Instruction]) -> Bundle:
    group_names = {Path(instruction.source_file).stem for instruction in instructions}
    anchors = {
        name: Anchor(anchor=AnchorDetails(comment=f"anchor {name}"))
        for group in group_names
        for name in (f"section_{group}", group)
    }
    return Bundle(anchors=anchors)


def test_render_sections_uses_source_groups_and_native_selector_arities() -> None:
    instructions = [
        instruction_metadata(
            constructor="NOP",
            source_file="model/instructions/data_movement.sail",
            opcode="00000",
            operand_count=0,
        ),
        instruction_metadata(
            constructor="LDW",
            source_file="model/instructions/memory.sail",
            opcode="00001",
            operand_count=3,
        ),
    ]
    bundle = native_bundle(instructions)
    metadata = Metadata(word_width=16, instructions=instructions)

    rendered = render_sections(bundle, metadata)

    assert rendered.index("section_data_movement") < rendered.index("section_memory")
    assert 'clause="NOP()"' in rendered
    assert 'clause="LDW(_, _, _)"' in rendered
    assert "sail::decode[grep=Some\\(LDW\\(]" in rendered
    assert "[#insn-NOP%breakable]" in rendered


def test_render_sections_rejects_missing_group_anchor() -> None:
    instruction = instruction_metadata(
        constructor="NOP",
        source_file="model/instructions/data_movement.sail",
        opcode="00000",
        operand_count=0,
    )
    bundle = native_bundle([instruction])
    anchors = dict(bundle.anchors)
    anchors.pop("data_movement")
    bundle = Bundle(anchors=anchors)

    with pytest.raises(SectionsError, match="anchor data_movement"):
        render_sections(bundle, Metadata(word_width=16, instructions=[instruction]))


def test_native_sections_follow_renamed_constructor(tmp_path: Path) -> None:
    plugin_value = os.environ.get("TARA_DOC_PLUGIN")
    if not plugin_value:
        pytest.skip("TARA_DOC_PLUGIN is only set in the documentation build environment")

    shutil.copytree(MODEL, tmp_path / "model")
    documentation_directory = tmp_path / "doc"
    documentation_directory.mkdir()
    shutil.copyfile(TEMPLATE, documentation_directory / "tara.adoc")
    shutil.copyfile(SECTIONS_LAYOUT, documentation_directory / "sections.rb")
    assert "include::instructions.adoc[]" in TEMPLATE.read_text(encoding="utf-8")

    movement_path = tmp_path / "model/instructions/data_movement.sail"
    movement = movement_path.read_text(encoding="utf-8")
    for old, new in (
        ("union clause instruction = NOP : unit", "union clause instruction = IDLE : unit"),
        ("encode(NOP())", "encode(IDLE())"),
        ("Some(NOP())", "Some(IDLE())"),
        ("execute(NOP())", "execute(IDLE())"),
    ):
        assert old in movement
        movement = movement.replace(old, new, 1)
    movement_path.write_text(movement, encoding="utf-8")

    syntax_path = tmp_path / "model/syntax.sail"
    syntax = syntax_path.read_text(encoding="utf-8")
    old_mapping = 'mapping clause assembly = NOP() <-> "NOP"'
    assert old_mapping in syntax
    syntax_path.write_text(
        syntax.replace(old_mapping, 'mapping clause assembly = IDLE() <-> "NOP"', 1),
        encoding="utf-8",
    )

    bundle_path = documentation_directory / "tara.json"
    documentation = subprocess.run(
        [
            "sail",
            "--doc",
            "--doc-embed",
            "plain",
            "--doc-bundle",
            "tara.json",
            "-o",
            "doc",
            "model/syntax.sail",
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert documentation.returncode == 0, documentation.stdout + documentation.stderr

    metadata_path = documentation_directory / "tables.json"
    extraction = subprocess.run(
        [
            "sail",
            "-plugin",
            plugin_value,
            "--doc-tables",
            "--doc-tables-decode",
            "decode",
            "--doc-tables-encode",
            "encode",
            "--doc-tables-assembly",
            "assembly",
            "-o",
            str(metadata_path),
            "model/syntax.sail",
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert extraction.returncode == 0, extraction.stdout + extraction.stderr

    bundle = msgspec.json.decode(bundle_path.read_bytes(), type=Bundle)
    metadata = msgspec.json.decode(metadata_path.read_bytes(), type=Metadata)
    sections = render_sections(bundle, metadata)
    instruction_path = documentation_directory / "instructions.adoc"
    instruction_path.write_text(sections, encoding="utf-8")
    formats, opcodes = render_tables(metadata)
    (documentation_directory / "formats.adoc").write_text(formats, encoding="utf-8")
    (documentation_directory / "opcodes.adoc").write_text(opcodes, encoding="utf-8")

    html_path = documentation_directory / "tara.html"
    render = subprocess.run(
        [
            "asciidoctor",
            "-r",
            "asciidoctor-sail",
            "-r",
            str(documentation_directory / "sections.rb"),
            "--failure-level",
            "WARN",
            "-o",
            str(html_path),
            str(documentation_directory / "tara.adoc"),
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert render.returncode == 0, render.stdout + render.stderr

    rendered = InstructionListings()
    rendered.feed(html_path.read_text(encoding="utf-8"))
    expected_constructors = {instruction.constructor for instruction in metadata.instructions}
    assert "IDLE" in rendered.instruction_heading_levels
    assert "NOP" not in rendered.instruction_heading_levels
    assert set(rendered.listings) == expected_constructors

    sources = read_instruction_sources(bundle_path)
    for instruction in metadata.instructions:
        expected_listings, _comment = sources[instruction.constructor]
        actual_listings = tuple(
            normalize_document_text(listing)
            for listing in rendered.listings[instruction.constructor]
        )
        assert actual_listings == tuple(
            normalize_document_text(listing) for listing in expected_listings
        ), instruction.constructor
