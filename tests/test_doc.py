"""The specification of TARA, which `tara.specification` writes from the Sail model: its opcode table
and its formats against TARA Studio's, which the emulators' disassembly is checked against too
(test_disasm.py), and the documents themselves."""

import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest
from src.simulation.cpu import FMT, OP_NAME

from tara.asciidoc import code as asciidoc_code
from tara.asciidoc import plain, render_asciidoc
from tara.document import (
    FormatTable,
    OpcodeRow,
    OpcodeTable,
    Specification,
    SpecificationError,
    build,
    instruction_anchor,
)
from tara.instructions import (
    Encoding,
    Field,
    Role,
    UnknownFormat,
    UnsupportedClause,
    format_name,
    parse_encoding,
    parse_syntax,
)
from tara.latex import ListingMismatch, escape, render_latex, typeset_words
from tara.prose import BadComment, Bullets, Code, Paragraph, Words, parse_prose
from tara.sail_doc import Clause, Macros, MissingLocations, OtherPattern, Source, parse_bundle

MODEL = Path(__file__).parents[1] / "model"
PREFIX = "tara"
ENTRY_POINT = Path("model/syntax.sail")
# The commands of just/doc.just that Sail documents the model with.
BUNDLE_ARGUMENTS = (
    "--doc",
    "--doc-embed",
    "plain",
    "--doc-embed-with-location",
    "--doc-bundle",
    "tara.json",
    "-o",
    "doc",
)


@dataclass(frozen=True, kw_only=True)
class SailOutput:
    """What Sail writes about a model: the bundle of its documentation, and its LaTeX macros."""

    bundle: Path
    commands: Path


def run_sail(directory: Path, *arguments: str) -> None:
    result = subprocess.run(["sail", *arguments], cwd=directory, capture_output=True, text=True)
    if result.returncode:
        pytest.fail(f"sail {' '.join(arguments)} failed:\n{result.stdout}{result.stderr}")


def copy_model(directory: Path) -> Path:
    """A copy of the model in `directory`, where Sail may run: it records the places of the
    definitions for a file that it is given by a relative path, and leaves a cache behind."""

    shutil.copytree(MODEL, directory / "model")
    return directory


def write_bundle(directory: Path, model: Path = ENTRY_POINT) -> Path:
    """The documentation bundle that Sail writes for the model in `directory`."""

    run_sail(directory, *BUNDLE_ARGUMENTS, str(model))
    return directory / "doc/tara.json"


def write_commands(directory: Path) -> Path:
    """The LaTeX macros that Sail writes for the model in `directory`."""

    latex = directory / "latex"
    latex.mkdir()
    run_sail(latex, "--latex", "--latex-prefix", PREFIX, str(directory / ENTRY_POINT))
    return latex / "sail_latex/commands.tex"


@pytest.fixture(scope="session")
def sail_output(tmp_path_factory: pytest.TempPathFactory) -> SailOutput:
    directory = copy_model(tmp_path_factory.mktemp("sail"))
    return SailOutput(bundle=write_bundle(directory), commands=write_commands(directory))


@pytest.fixture(scope="session")
def specification(sail_output: SailOutput) -> Specification:
    return build(parse_bundle(sail_output.bundle))


def tables(specification: Specification) -> tuple[OpcodeTable, FormatTable]:
    """The opcode table and the table of formats, which are in the instruction set's section."""

    blocks = [block for section in specification.sections for block in section.blocks]
    for section in specification.sections:
        for subsection in section.sections:
            blocks.extend(subsection.blocks)

    opcodes = next(block for block in blocks if isinstance(block, OpcodeTable))
    formats = next(block for block in blocks if isinstance(block, FormatTable))
    return opcodes, formats


def test_opcode_table_lists_every_opcode_with_its_format(specification: Specification) -> None:
    table, _formats = tables(specification)
    documented = {
        row.opcode: (row.mnemonic, row.format) for row in table.rows if isinstance(row, OpcodeRow)
    }

    assert documented == {opcode: (name, FMT[name]) for opcode, name in OP_NAME.items()}


def test_formats_list_their_instructions_in_opcode_order(specification: Specification) -> None:
    _table, formats = tables(specification)
    documented = {layout.name: layout.mnemonics for layout in formats.formats}

    expected = dict[str, tuple[str, ...]]()
    for _opcode, name in sorted(OP_NAME.items()):
        expected[FMT[name]] = (*expected.get(FMT[name], ()), name)

    assert documented == expected


def test_formats_span_the_instruction_word(specification: Specification) -> None:
    _table, formats = tables(specification)

    assert {sum(field.width for field in layout.fields) for layout in formats.formats} == {16}


def test_both_documents_have_an_entry_for_every_instruction(
    specification: Specification, sail_output: SailOutput
) -> None:
    latex = render_latex(specification, Macros.parse(sail_output.commands, prefix=PREFIX))
    asciidoc = render_asciidoc(specification)

    for name in OP_NAME.values():
        anchor = instruction_anchor(name)
        assert f"\\begin{{instruction}}{{{anchor}}}{{{name}}}" in latex
        assert f"[#{anchor}]\n==== {name}\n" in asciidoc


def test_listings_of_instructions_are_the_four_clauses(
    specification: Specification, sail_output: SailOutput
) -> None:
    latex = render_latex(specification, Macros.parse(sail_output.commands, prefix=PREFIX))
    entry = latex.split(r"\begin{instruction}{insn-ADD}")[1].split(r"\end{instruction}")[0]

    macros = re.findall(r"^\\(tarafcl\w+)$", entry, re.MULTILINE)
    assert macros == [
        f"tarafclADD{function}" for function in ("assembly", "encode", "decode", "execute")
    ]


def test_the_syntax_of_an_instruction_is_read_from_its_assembly_clause(
    specification: Specification,
) -> None:
    table, _formats = tables(specification)
    syntax = {row.mnemonic: row.syntax for row in table.rows if isinstance(row, OpcodeRow)}

    assert syntax["LDW"] == "LDW rd, off(base)"
    assert syntax["ADDI"] == "ADDI rd, imm"
    assert syntax["JMP"] == "JMP off"
    assert syntax["RET"] == "RET"


def test_an_instruction_without_a_description_is_refused(tmp_path: Path) -> None:
    directory = copy_model(tmp_path)
    source = directory / "model/instructions/data_movement.sail"
    source.write_text(re.sub(r"/\*! Does nothing\..*?\*/\n", "", source.read_text(), flags=re.S))

    with pytest.raises(SpecificationError, match="NOP has no documentation comment"):
        build(parse_bundle(write_bundle(directory)))


def test_a_listing_that_is_not_the_source_is_refused(tmp_path: Path) -> None:
    """Sail 0.20 typesets the wrong clause for the first clause of a file that starts with code."""

    directory = copy_model(tmp_path)
    source = directory / "model/instructions/comparison.sail"
    source.write_text(source.read_text().split("$anchor comparison\n\n")[1])
    specification = build(parse_bundle(write_bundle(directory)))
    macros = Macros.parse(write_commands(directory), prefix=PREFIX)

    with pytest.raises(ListingMismatch, match="tarafclSLTencode"):
        render_latex(specification, macros)


def test_a_bundle_without_locations_is_refused(tmp_path: Path) -> None:
    """Sail leaves the locations out when it is given the model by an absolute path."""

    directory = copy_model(tmp_path)
    bundle = write_bundle(directory, directory / ENTRY_POINT)

    with pytest.raises(MissingLocations, match="no locations"):
        parse_bundle(bundle)


def clause(text: str, body: str) -> Clause:
    """A clause of the model, as the bundle would have it."""

    def source(contents: str) -> Source:
        return Source(text=contents, file=Path("model/instructions/test.sail"), line=1, offset=0)

    return Clause(
        number=0,
        source=source(text),
        pattern=OtherPattern(kind="test"),
        body=source(body),
        comment=None,
    )


def test_the_syntax_of_an_instruction_follows_the_operands_of_its_assembly_clause() -> None:
    mov = clause("function clause assembly(MOV(rd, rs)) = ...", 'op2("MOV", reg(rd), reg(rs))')
    load = clause(
        "function clause assembly(LDW(rd, base, off)) = ...", 'op2("LDW", reg(rd), mem(off, base))'
    )
    jump = clause("function clause assembly(JMP(off)) = ...", 'op1("JMP", dec_str(signed(off)))')

    assert [parse_syntax(c) for c in (mov, load, jump)] == [
        "MOV rd, rs",
        "LDW rd, off(base)",
        "JMP off",
    ]


def test_an_assembly_clause_with_an_unknown_operand_is_refused() -> None:
    odd = clause("function clause assembly(X(r)) = ...", 'op1("X", hex_str(unsigned(r)))')

    with pytest.raises(UnsupportedClause, match="hex_str"):
        parse_syntax(odd)


def test_the_encoding_of_an_instruction_is_read_from_its_decode_clause() -> None:
    mov = clause(
        "function clause decode(0b00010 @ rd : regidx @ rs : regidx @ _ : bits(5)) = Some(MOV(rd, rs))",
        "Some(MOV(rd, rs))",
    )

    encoding = parse_encoding(mov, function="decode", widths={"regidx": 3})

    assert encoding.opcode == 2
    assert encoding.opcode_width == 5
    assert encoding.fields == (
        Field(name="rd", role=Role.REGISTER, width=3),
        Field(name="rs", role=Role.REGISTER, width=3),
        Field(name="_", role=Role.PADDING, width=5),
    )
    assert format_name("MOV", encoding) == "F2"


def test_fields_that_match_no_format_are_refused() -> None:
    odd = Encoding(
        opcode=1, opcode_width=5, fields=(Field(name="x", role=Role.IMMEDIATE, width=11),)
    )

    with pytest.raises(UnknownFormat, match="no format has the fields"):
        format_name("ODD", odd)


def test_latex_text_has_curly_quotes_and_long_minus_signs() -> None:
    typeset = typeset_words('"quoted" -5 and a-b (-2)', first=True)

    assert typeset == (r"\textquotedblleft{}quoted\textquotedblright{} $-$5 and a-b ($-$2)")


def test_latex_escapes_what_it_would_otherwise_run() -> None:
    assert escape("a_b #1 {x} 50% >>") == r"a\_b \#1 \{x\} 50\% \textgreater{}\textgreater{}"


def test_asciidoc_passes_text_that_it_would_otherwise_change() -> None:
    assert plain("Ordinary text, (see 12).") == "Ordinary text, (see 12)."
    assert plain("a (C) b") == "pass:c[a (C) b]"
    assert plain("PC + 2 [x]") == "pass:c[PC + 2 [x\\]]"
    assert asciidoc_code("PC + 2") == "`+PC + 2+`"
    assert asciidoc_code("a+") == "`pass:c[a+]`"


def test_prose_is_paragraphs_lists_and_code() -> None:
    prose = parse_prose(
        " One `a  b`\ntwo.\n\nNext:\n\n- `x` first\nsecond\n* `y`\n\n", where="test"
    )

    assert prose.blocks == (
        Paragraph(spans=(Words(text="One "), Code(text="a b"), Words(text=" two."))),
        Paragraph(spans=(Words(text="Next:"),)),
        Bullets(
            items=(
                (Code(text="x"), Words(text=" first second")),
                (Code(text="y"),),
            )
        ),
    )


@pytest.mark.parametrize(
    ("comment", "problem"),
    [
        ("an `open code span", "unmatched backquote"),
        ("an empty `` span", "empty code span"),
        ("a non-ASCII é", "other than ASCII"),
        ("  \n ", "is empty"),
    ],
)
def test_prose_outside_the_subset_is_refused(comment: str, problem: str) -> None:
    with pytest.raises(BadComment, match=problem):
        parse_prose(comment, where="test")
