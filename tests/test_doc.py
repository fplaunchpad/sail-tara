"""Sail-derived instruction tables and native documentation render together."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import msgspec
import pytest
from src.simulation.cpu import OP_NAME

from helpers.doc import InstructionListings, normalize_document_text, read_instruction_sources
from tara.doc_tables import Field, Instruction, Metadata, format_names, render_tables
from tara.table import Cell, Code, Column, Row, Table, TableAlignment, TableAttributes, Text

ROOT = Path(__file__).parents[1]
MODEL = ROOT / "model"
TEMPLATE = ROOT / "doc/tara.adoc"
STYLESHEET = ROOT / "doc/tara.css"
FORMAT_CONFIG = ROOT / "doc/sail_config.json"
PRETTIER_CONFIG = ROOT / ".prettierrc.json"
ENTRY_POINT = "model/syntax.sail"
SMALL_ISA_SOURCE = """\
default Order dec
$include <prelude.sail>
$include <mapping.sail>
$include <dec_bits.sail>
overload operator ^ = {concat_str}

type word = bits(12)
scattered union instruction
union clause instruction = Tiny : (bits(2), bits(3))
union clause instruction = Stop : unit
end instruction

val encode : instruction -> word
scattered function encode
function clause encode(Tiny(first, second)) = 0x2 @ first @ second @ 0b000
function clause encode(Stop()) = 0x1 @ 0b00000000
end encode

val decode : word -> option(instruction)
scattered function decode
function clause decode(0x2 @ first : bits(2) @ second : bits(3) @ _ : bits(3)) =
  Some(Tiny(first, second))
function clause decode(0x1 @ _ : bits(8)) = Some(Stop())
function clause decode(_) = None()
end decode

mapping separator : unit <-> string = { () <-> ":" }
mapping repeat_operand : bits(3) <-> string = {
  forwards value => dec_bits_3(value) ^ "/" ^ dec_bits_3(value),
  backwards _ if false => 0b000
}

val assembly : instruction <-> string
scattered mapping assembly
mapping clause assembly = Stop() <-> "STOP"
mapping clause assembly = Tiny(second, first) <-> "TINY" ^ separator() ^ repeat_operand(first) ^ "/" ^ dec_bits_2(second)
end assembly

"""


def run_sail_documentation(directory: Path, plugin: Path) -> Path:
    model_directory = directory / "model"
    documentation_model = directory / "doc/model"
    sources = sorted(model_directory.glob("*.sail")) + sorted(
        (model_directory / "instructions").glob("*.sail")
    )
    for source in sources:
        relative_source = source.relative_to(directory)
        destination = documentation_model / relative_source.relative_to("model")
        destination.parent.mkdir(parents=True, exist_ok=True)
        formatted = subprocess.run(
            [
                "sail",
                "--sail-config",
                str(FORMAT_CONFIG),
                "--fmt",
                "--fmt-emit",
                "stdout",
                str(relative_source),
            ],
            cwd=directory,
            capture_output=True,
            text=True,
            check=False,
        )
        assert formatted.returncode == 0, formatted.stdout + formatted.stderr
        destination.write_text(formatted.stdout, encoding="utf-8")

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
            "doc/" + ENTRY_POINT,
        ],
        cwd=directory,
        capture_output=True,
        text=True,
        check=False,
    )
    assert documentation.returncode == 0, documentation.stdout + documentation.stderr

    metadata = directory / "doc/tables.json"
    extraction = run_sail_tables(directory, plugin, metadata)
    assert extraction.returncode == 0, extraction.stdout + extraction.stderr
    assert metadata.is_file()
    return metadata


def run_sail_tables(
    directory: Path,
    plugin: Path,
    metadata: Path,
    entry_point: str = ENTRY_POINT,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "sail",
            "-plugin",
            str(plugin),
            "--doc-tables",
            "--doc-tables-decode",
            "decode",
            "--doc-tables-encode",
            "encode",
            "--doc-tables-assembly",
            "assembly",
            "-o",
            str(metadata),
            entry_point,
        ],
        cwd=directory,
        capture_output=True,
        text=True,
        check=False,
    )


def render_native_document(directory: Path, metadata: Path) -> Path:
    environment = os.environ.copy()
    tools_directory = str(ROOT / "tools")
    existing_python_path = environment.get("PYTHONPATH")
    environment["PYTHONPATH"] = os.pathsep.join(
        path for path in (tools_directory, existing_python_path) if path
    )
    tables = subprocess.run(
        [
            sys.executable,
            "-m",
            "tara.doc_tables",
            "--metadata",
            str(metadata),
            "--out",
            str(directory / "doc"),
        ],
        cwd=directory,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    assert tables.returncode == 0, tables.stdout + tables.stderr

    sections = subprocess.run(
        [
            sys.executable,
            "-m",
            "tara.doc_sections",
            "--bundle",
            str(directory / "doc/tara.json"),
            "--metadata",
            str(metadata),
            "--out",
            str(directory / "doc/instructions.adoc"),
        ],
        cwd=directory,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    assert sections.returncode == 0, sections.stdout + sections.stderr

    html_path = directory / "doc/tara.html"
    render = subprocess.run(
        [
            "asciidoctor",
            "-r",
            "asciidoctor-sail",
            "-r",
            str(ROOT / "doc/sections.rb"),
            "--failure-level",
            "WARN",
            "-a",
            "stylesheet=tara.css",
            "-o",
            str(html_path),
            str(directory / "doc/tara.adoc"),
        ],
        cwd=directory / "render",
        capture_output=True,
        text=True,
        check=False,
    )
    assert render.returncode == 0, render.stdout + render.stderr
    formatted = subprocess.run(
        ["prettier", "--write", str(html_path)],
        cwd=directory,
        capture_output=True,
        text=True,
        check=False,
    )
    assert formatted.returncode == 0, formatted.stdout + formatted.stderr
    return html_path


def test_native_sail_docs_render_tables_and_all_instruction_sources(tmp_path: Path) -> None:
    plugin_value = os.environ.get("TARA_DOC_PLUGIN")
    if not plugin_value:
        pytest.skip("TARA_DOC_PLUGIN is only set in the documentation build environment")

    document_directory = tmp_path / "doc"
    document_directory.mkdir()
    (tmp_path / "render").mkdir()
    shutil.copytree(MODEL, tmp_path / "model")
    shutil.copyfile(TEMPLATE, document_directory / "tara.adoc")
    shutil.copyfile(STYLESHEET, document_directory / "tara.css")
    shutil.copyfile(PRETTIER_CONFIG, tmp_path / ".prettierrc.json")

    machine_path = tmp_path / "model/machine.sail"
    machine = machine_path.read_text(encoding="utf-8")
    machine = machine.replace(
        "The TARA Instruction Set Architecture",
        "Native bundle title marker",
        1,
    )
    machine = machine.replace("== Machine state */", "== Native machine section marker */", 1)
    machine_path.write_text(machine, encoding="utf-8")

    syntax_path = tmp_path / ENTRY_POINT
    syntax = syntax_path.read_text(encoding="utf-8")
    syntax = syntax.replace("reg_name", "register_to_text")
    original_movement = '"MOV " ^ register_to_text(rd) ^ ", "'
    assert original_movement in syntax
    syntax = syntax.replace(original_movement, '"MOV " ^ register_to_text(rd) ^ "; "', 1)
    syntax_path.write_text(syntax, encoding="utf-8")
    template = (document_directory / "tara.adoc").read_text(encoding="utf-8")
    template = template.replace("reg_name", "register_to_text")
    (document_directory / "tara.adoc").write_text(template, encoding="utf-8")

    movement_path = tmp_path / "model/instructions/data_movement.sail"
    movement = movement_path.read_text(encoding="utf-8")
    movement = movement.replace(
        "Does nothing.", "Native instruction comment marker. Does nothing.", 1
    )
    movement_path.write_text(movement, encoding="utf-8")

    metadata_path = run_sail_documentation(tmp_path, Path(plugin_value))
    metadata = msgspec.json.decode(metadata_path.read_bytes(), type=Metadata)
    sources = read_instruction_sources(document_directory / "tara.json")
    html_path = render_native_document(tmp_path, metadata_path)

    rendered = InstructionListings()
    rendered.feed(html_path.read_text(encoding="utf-8"))
    rendered_text = normalize_document_text("".join(rendered.text))
    assert "sail::" not in rendered_text
    assert "Native bundle title marker" in rendered_text
    assert "Native machine section marker" in rendered_text
    assert "Native instruction comment marker" in rendered_text
    assert "The program counter" in rendered_text
    assert "PC wraps around" in rendered_text
    assert "<code>pc_mask</code>" in html_path.read_text(encoding="utf-8")
    assert all("The program counter" not in block for block in rendered.preformatted)
    assert len(metadata.instructions) == len(OP_NAME) == 27
    assert all(Path(item.source_file).suffix == ".sail" for item in metadata.instructions)
    assert f'rowspan="{len(format_names(metadata))}"' in html_path.read_text(encoding="utf-8")
    assert {int(item.opcode_bits, 2): item.constructor for item in metadata.instructions} == OP_NAME
    assert set(rendered.listings) == {item.constructor for item in metadata.instructions}
    expected_instruction_links = {item.constructor for item in metadata.instructions}
    assert rendered.toc_instruction_links == expected_instruction_links
    assert rendered.toc_instruction_code_links == expected_instruction_links
    assert set(rendered.instruction_heading_levels) == expected_instruction_links
    assert set(rendered.instruction_heading_families) == expected_instruction_links
    assert set(rendered.instruction_heading_levels.values()) == {4}
    assert "tara.css" in rendered.stylesheets or "JetBrainsMono" in rendered_text

    for instruction in metadata.instructions:
        listings, comment = sources[instruction.constructor]
        assert all(source.startswith("function clause ") for source in listings[:3])
        assert listings[3].startswith("mapping clause assembly ")
        actual = tuple(
            normalize_document_text(line) for line in rendered.listings[instruction.constructor]
        )
        expected = tuple(normalize_document_text(line) for line in listings)
        assert actual == expected, instruction.constructor
        assert normalize_document_text(comment) in rendered_text, instruction.constructor
    mov = next(item for item in metadata.instructions if item.constructor == "MOV")
    assert ";" in normalize_document_text(mov.syntax)
    runtime = subprocess.run(
        ["sail", "-i", ENTRY_POINT],
        cwd=tmp_path,
        input="assembly(MOV(0b001, 0b010))\n:run\n:quit\n",
        capture_output=True,
        text=True,
        check=False,
    )
    assert runtime.returncode == 0, runtime.stdout + runtime.stderr
    assert 'Result = "MOV R1; R2"' in runtime.stdout

    opcode_table = next(
        table
        for table in rendered.tables
        if table and normalize_document_text(table[0][0]) == "Opcode"
    )
    opcode_table_index = rendered.tables.index(opcode_table)
    assert rendered.table_header_alignments[opcode_table_index] == ["center"] * len(opcode_table[0])
    assert rendered.table_cell_alignments[opcode_table_index][1][3] == ("center", "middle")
    format_table_index = next(
        index
        for index, table in enumerate(rendered.tables)
        if table and normalize_document_text(table[0][0]) == "Format"
    )
    format_table = rendered.tables[format_table_index]
    assert rendered.table_header_alignments[format_table_index] == ["center"] * len(format_table[0])
    assert all(
        vertical == "middle"
        for table in rendered.table_cell_alignments
        for row in table
        for _, vertical in row
    )
    assert rendered.table_cell_alignments[format_table_index][1][0] == ("center", "middle")
    all_opcode_rows = [[normalize_document_text(cell) for cell in row] for row in opcode_table[1:]]
    opcode_rows = [row for row in all_opcode_rows if row[0].isdigit()]
    expected_opcodes = sorted(metadata.instructions, key=lambda item: int(item.opcode_bits, 2))
    assert [int(row[0]) for row in opcode_rows] == [
        int(item.opcode_bits, 2) for item in expected_opcodes
    ]
    for row, instruction in zip(opcode_rows, expected_opcodes, strict=True):
        assert row[2] == instruction.opcode_bits
        assert row[3] == instruction.constructor
        assert row[4] == instruction.syntax
    assert [row[0] for row in all_opcode_rows if not row[0].isdigit()] == ["27-31"]


def test_renderer_supports_arbitrary_word_width_and_more_than_nine_formats(tmp_path: Path) -> None:
    opcodes = (0, 1, 3, 4, 5, 6, 7, 8, 9, 10)
    instructions = [
        Instruction(
            constructor=f"I{index}",
            opcode_bits=f"{opcodes[index]:04b}",
            syntax=f"I{index}",
            source_file="small.sail",
            operand_count=1,
            fields=[Field(name="opcode", width=4), Field(name=f"field{index}", width=4)],
        )
        for index in range(10)
    ]
    encoded = json.dumps(
        {
            "word_width": 8,
            "instructions": [
                {
                    "constructor": instruction.constructor,
                    "opcode_bits": instruction.opcode_bits,
                    "syntax": instruction.syntax,
                    "source_file": instruction.source_file,
                    "operand_count": instruction.operand_count,
                    "fields": [
                        {"name": field.name, "width": field.width} for field in instruction.fields
                    ],
                }
                for instruction in instructions
            ],
        }
    ).encode()
    metadata = msgspec.json.decode(encoded, type=Metadata)

    formats, opcodes = render_tables(metadata)

    assert 'width="92%",role="center"]' in formats.splitlines()[0]
    assert 'width="72%",role="center"]' in opcodes.splitlines()[0]
    assert (
        formats.index("|[[fmt-F1]]") < formats.index("|[[fmt-F2]]") < formats.index("|[[fmt-F10]]")
    )
    assert "^.^|Format ^.^|7 ^.^|6 ^.^|5 ^.^|4 ^.^|3 ^.^|2 ^.^|1 ^.^|0 ^.^|Instructions" in formats
    assert ".^|0 .^|`+0+` .^|`+0000+` ^.^|<<insn-I0,`+I0+`>>" in opcodes
    assert ".^|2 .^|`+2+` .^|`+0010+` 3+.^|unassigned" in opcodes
    assert ".^|11-15 .^|`+B+`-`+F+` .^|`+1011+`-`+1111+` 3+.^|unassigned" in opcodes
    source = tmp_path / "tables.adoc"
    output = tmp_path / "tables.html"
    source.write_text(formats + "\n" + opcodes, encoding="utf-8")
    result = subprocess.run(
        ["asciidoctor", "-o", str(output), str(source)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    html = output.read_text(encoding="utf-8")
    rendered = InstructionListings()
    rendered.feed(html)
    assert len(rendered.tables) == 2
    assert 'rowspan="10"' in html
    assert rendered.table_header_alignments == [["center"] * 10, ["center"] * 6]


def test_invalid_metadata_fails_without_creating_output(tmp_path: Path) -> None:
    metadata_path = tmp_path / "invalid.json"
    metadata_path.write_text(
        json.dumps(
            {
                "word_width": 8,
                "instructions": [
                    {
                        "constructor": "BAD",
                        "opcode_bits": "0000",
                        "syntax": "BAD",
                        "source_file": "small.sail",
                        "operand_count": 1,
                        "fields": [{"name": "opcode", "width": 4}, {"name": "x", "width": 3}],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    output = tmp_path / "tables"

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "tara.doc_tables",
            "--metadata",
            str(metadata_path),
            "--out",
            str(output),
        ],
        cwd=ROOT,
        env={**os.environ, "PYTHONPATH": str(ROOT / "tools")},
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert not output.exists()


def test_table_serializer_preserves_headers_spans_and_pipe_content(tmp_path: Path) -> None:
    table = Table(
        columns=(Column(), Column(repeat=2)),
        rows=(
            Row(
                cells=tuple(
                    Cell(content=(Text(value=value),)) for value in ("Left", "Middle", "Right")
                )
            ),
            Row(
                cells=(
                    Cell(content=(Text(value="plain|pipe"),)),
                    Cell(content=(Code(value="code|pipe"),), colspan=2),
                )
            ),
        ),
        attributes=TableAttributes(width=75, alignment=TableAlignment.CENTER),
    )
    assert '[cols="1,2*1", options="header",width="75%",role="center"]' in table.to_asciidoc()
    source = tmp_path / "table.adoc"
    output = tmp_path / "table.html"
    source.write_text("= Table test\n\n" + table.to_asciidoc(), encoding="utf-8")

    result = subprocess.run(
        ["asciidoctor", "-o", str(output), str(source)],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    html = output.read_text(encoding="utf-8")
    assert "width: 75%;" in html
    assert 'class="tableblock frame-all grid-all center"' in html
    rendered = InstructionListings()
    rendered.feed(html)
    assert len(rendered.tables) == 1
    assert rendered.tables[0][0] == ["Left", "Middle", "Right"]
    assert rendered.tables[0][1] == ["plain|pipe", "code|pipe"]
    assert rendered.table_spans[0] == [[1, 1, 1], [1, 2]]


def test_table_rowspans_merge_cells_and_render_in_html(tmp_path: Path) -> None:
    table = Table(
        columns=(Column(), Column()),
        rows=(
            Row(
                cells=(
                    Cell(content=(Text(value="Opcode"),), rowspan=2),
                    Cell(content=(Text(value="First"),)),
                )
            ),
            Row(cells=(Cell(content=(Text(value="Second"),)),)),
        ),
        attributes=TableAttributes(header=False),
    )
    source = tmp_path / "rowspan.adoc"
    output = tmp_path / "rowspan.html"
    source.write_text("= Row span\n\n" + table.to_asciidoc(), encoding="utf-8")

    result = subprocess.run(
        ["asciidoctor", "-o", str(output), str(source)],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert 'rowspan="2"' in output.read_text(encoding="utf-8")


def test_table_merges_equal_cells_at_the_same_column_range() -> None:
    table = Table(
        columns=(Column(repeat=4),),
        rows=tuple(
            Row(cells=tuple(Cell(content=(Text(value=value),)) for value in values))
            for values in (
                ("opcode", "rd", "rs", "first"),
                ("opcode", "rd", "rs", "second"),
                ("opcode", "rd", "other", "first"),
            )
        ),
        attributes=TableAttributes(header=False),
    )

    rendered = table.merge_adjacent_equal_cells().to_asciidoc()

    assert ".3+.^|opcode" in rendered
    assert ".3+.^|rd" in rendered
    assert ".2+.^|rs" in rendered
    assert ".2+.^|first" not in rendered


def test_table_merge_preserves_the_header_row() -> None:
    table = Table(
        columns=(Column(),),
        rows=tuple(Row(cells=(Cell(content=(Text(value="opcode"),)),)) for _ in range(3)),
    )

    rendered = table.merge_adjacent_equal_cells().to_asciidoc()

    assert rendered.count(".2+.^|opcode") == 1
    assert rendered.splitlines()[2] == ".^|opcode"


def test_table_merge_all_columns_preserves_fully_covered_row(tmp_path: Path) -> None:
    table = Table(
        columns=(Column(),),
        rows=tuple(Row(cells=(Cell(content=(Text(value="opcode"),)),)) for _ in range(2)),
        attributes=TableAttributes(header=False),
    ).merge_adjacent_equal_cells()
    source = tmp_path / "fully-covered-row.adoc"
    output = tmp_path / "fully-covered-row.html"
    source.write_text("= Fully covered row\n\n" + table.to_asciidoc(), encoding="utf-8")

    result = subprocess.run(
        ["asciidoctor", "-o", str(output), str(source)],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert table.rows[1].cells == ()
    assert 'rowspan="2"' in output.read_text(encoding="utf-8")


def test_table_rejects_invalid_rowspan_coverage() -> None:
    with pytest.raises(ValueError, match="row 1 covers 1 of 2 columns"):
        Table(
            columns=(Column(repeat=2),),
            rows=(Row(cells=(Cell(content=(Text(value="short"),)),)),),
        )

    with pytest.raises(ValueError, match="rowspan extends beyond the table's final row"):
        Table(
            columns=(Column(),),
            rows=(Row(cells=(Cell(content=(Text(value="long"),), rowspan=2),)),),
        )


@pytest.mark.parametrize("width", [0, 101, True])
def test_table_attributes_reject_invalid_width(width: int) -> None:
    with pytest.raises(ValueError, match="table width must be an integer from 1 to 100"):
        TableAttributes(width=width)


@pytest.mark.parametrize(
    ("relative_path", "old", "new"),
    [
        (
            "model/instructions/data_movement.sail",
            "function clause decode(0b00000 @ _ : bits(11))",
            "function clause decode(0b0000 @ _ : bits(11))",
        ),
        (
            "model/syntax.sail",
            'mapping clause assembly = NOP() <-> "NOP"',
            'mapping clause assembly = NOP() <-> if true then "NOP" else "NOP"',
        ),
        (
            "model/instructions/data_movement.sail",
            "function clause encode(MOV(rd, rs)) = 0b00010 @ rd @ rs @ 0b00000",
            "function clause encode(MOV(rd, rs)) = 0b00010 @ rs @ rd @ 0b00000",
        ),
    ],
    ids=("inconsistent-opcode-width", "unsupported-assembly-expression", "encode-bit-order"),
)
def test_invalid_sail_source_fails_without_partial_metadata(
    tmp_path: Path, relative_path: str, old: str, new: str
) -> None:
    plugin_value = os.environ.get("TARA_DOC_PLUGIN")
    if not plugin_value:
        pytest.skip("TARA_DOC_PLUGIN is only set in the documentation build environment")

    shutil.copytree(MODEL, tmp_path / "model")
    source = tmp_path / relative_path
    contents = source.read_text(encoding="utf-8")
    assert old in contents
    source.write_text(contents.replace(old, new, 1), encoding="utf-8")
    output = tmp_path / "invalid.json"

    result = run_sail_tables(tmp_path, Path(plugin_value), output)

    assert result.returncode != 0
    assert Path(relative_path).name in result.stdout + result.stderr
    assert not output.exists()


def test_small_sail_isa_supports_generic_layout_and_mapping_expressions(tmp_path: Path) -> None:
    plugin_value = os.environ.get("TARA_DOC_PLUGIN")
    if not plugin_value:
        pytest.skip("TARA_DOC_PLUGIN is only set in the documentation build environment")

    source = SMALL_ISA_SOURCE
    source_path = tmp_path / "small.sail"
    source_path.write_text(source, encoding="utf-8")
    metadata_path = tmp_path / "small.json"
    result = run_sail_tables(tmp_path, Path(plugin_value), metadata_path, "small.sail")

    assert result.returncode == 0, result.stdout + result.stderr
    metadata = msgspec.json.decode(metadata_path.read_bytes(), type=Metadata)
    assert metadata.word_width == 12
    assert [(item.constructor, item.opcode_bits) for item in metadata.instructions] == [
        ("Stop", "0001"),
        ("Tiny", "0010"),
    ]
    assert {item.constructor: item.operand_count for item in metadata.instructions} == {
        "Stop": 0,
        "Tiny": 2,
    }
    tiny = next(item for item in metadata.instructions if item.constructor == "Tiny")
    assert {item.source_file for item in metadata.instructions} == {"small.sail"}
    assert [(field.name, field.width) for field in tiny.fields] == [
        ("opcode", 4),
        ("first", 2),
        ("second", 3),
        ("padding", 3),
    ]
    assert tiny.syntax == "TINY:second/first"
    runtime = subprocess.run(
        ["sail", "-i", "small.sail"],
        cwd=tmp_path,
        input="assembly(Tiny(0b00, 0b101))\n:run\n:quit\n",
        capture_output=True,
        text=True,
        check=False,
    )
    assert runtime.returncode == 0, runtime.stdout + runtime.stderr
    assert 'Result = "TINY:5/5/0"' in runtime.stdout


def test_generic_bound_field_named_padding_is_rejected(tmp_path: Path) -> None:
    plugin_value = os.environ.get("TARA_DOC_PLUGIN")
    if not plugin_value:
        pytest.skip("TARA_DOC_PLUGIN is only set in the documentation build environment")

    source = SMALL_ISA_SOURCE.replace("second : bits(3)", "padding : bits(3)", 1)
    source = source.replace("Some(Tiny(first, second))", "Some(Tiny(first, padding))", 1)
    source_path = tmp_path / "small.sail"
    source_path.write_text(source, encoding="utf-8")
    output = tmp_path / "invalid-padding.json"

    result = run_sail_tables(tmp_path, Path(plugin_value), output, "small.sail")

    assert result.returncode != 0
    assert "small.sail" in result.stdout + result.stderr
    assert not output.exists()


def test_early_none_decode_wildcard_is_rejected(tmp_path: Path) -> None:
    plugin_value = os.environ.get("TARA_DOC_PLUGIN")
    if not plugin_value:
        pytest.skip("TARA_DOC_PLUGIN is only set in the documentation build environment")

    shutil.copytree(MODEL, tmp_path / "model")
    source_path = tmp_path / "model/tara.sail"
    source = source_path.read_text(encoding="utf-8")
    fallback = "function clause decode(_) = None()\n"
    first_include = '$include "instructions/data_movement.sail"'
    assert fallback in source
    assert first_include in source
    source = source.replace(fallback, "", 1)
    source = source.replace(first_include, fallback + first_include, 1)
    source_path.write_text(source, encoding="utf-8")
    output = tmp_path / "early-fallback.json"

    result = run_sail_tables(tmp_path, Path(plugin_value), output)

    assert result.returncode != 0
    assert "tara.sail" in result.stdout + result.stderr
    assert not output.exists()


def test_missing_instruction_union_constructor_fails_closed(tmp_path: Path) -> None:
    plugin_value = os.environ.get("TARA_DOC_PLUGIN")
    if not plugin_value:
        pytest.skip("TARA_DOC_PLUGIN is only set in the documentation build environment")

    shutil.copytree(MODEL, tmp_path / "model")
    movement_path = tmp_path / "model/instructions/data_movement.sail"
    movement = movement_path.read_text(encoding="utf-8")
    movement = movement.replace("function clause encode(NOP()) = 0b00000 @ 0b00000000000\n", "", 1)
    movement = movement.replace(
        "function clause decode(0b00000 @ _ : bits(11)) = Some(NOP())\n", "", 1
    )
    movement_path.write_text(movement, encoding="utf-8")
    syntax_path = tmp_path / ENTRY_POINT
    syntax = syntax_path.read_text(encoding="utf-8")
    syntax = syntax.replace('mapping clause assembly = NOP() <-> "NOP"\n', "", 1)
    syntax_path.write_text(syntax, encoding="utf-8")
    output = tmp_path / "incomplete.json"

    result = run_sail_tables(tmp_path, Path(plugin_value), output)

    assert result.returncode != 0
    assert "data_movement.sail" in result.stdout + result.stderr
    assert not output.exists()
