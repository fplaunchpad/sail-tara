"""The specification follows the model: each instruction's section shows the model's clauses, the
tables agree with TARA Studio, and the generator reads any instruction set whose encodings start
with a fixed-width opcode."""

import os
import subprocess
from pathlib import Path

import pytest
from src.simulation.cpu import OP_NAME

from helpers.doc import INSTRUCTION_SETS, Bundle, Specification, Workspace
from tara.asciidoc import Cell, Code, Column, LineBreak, Row, Table, Text
from tara.doc import (
    OPCODES,
    AnchorEntry,
    ConstructorEntry,
    Field,
    Fixed,
    Ignored,
    Instruction,
    InstructionSet,
    Operand,
    Selector,
    section_anchor,
)

needs_plugin = pytest.mark.skipif(
    "TARA_DOC_PLUGIN" not in os.environ, reason="needs the Sail plugin in tools/sail-doc"
)
MNEMONICS = sorted(OP_NAME.values())
HTML = "tara.html"
METADATA = "tables.json"
BUNDLE = "tara.json"
DATA_MOVEMENT = "model/instructions/data_movement.sail"
SYNTAX = "model/syntax.sail"


@pytest.fixture(scope="session")
def built(tmp_path_factory: pytest.TempPathFactory) -> Workspace:
    """The specification of the model as it is, built once."""

    workspace = Workspace.copy(tmp_path_factory.mktemp("specification"))
    workspace.build("doc", "html")
    return workspace


@pytest.fixture(scope="session")
def specification(built: Workspace) -> Specification:
    return Specification.read(built.output / HTML)


@needs_plugin
@pytest.mark.parametrize("mnemonic", MNEMONICS)
def test_section_shows_the_instruction_s_clauses(
    built: Workspace, specification: Specification, mnemonic: str
) -> None:
    clauses = Bundle.read(built.output / BUNDLE).clauses(mnemonic)

    assert len(clauses) == 3
    assert specification.listings(f"insn-{mnemonic}") == clauses


@needs_plugin
def test_opcode_table_agrees_with_studio(specification: Specification) -> None:
    _header, *rows = specification.table("Opcode")
    assigned = {int(row[0]): row[1].split()[0] for row in rows if row[0].isdecimal()}

    assert assigned == OP_NAME
    assert [row[0] for row in rows if not row[0].isdecimal()] == ["27-31"]


@needs_plugin
def test_format_table_lists_each_instruction_once(specification: Specification) -> None:
    _header, *rows = specification.table("Format")

    assert sorted(name for row in rows for name in row[-1].split(", ")) == MNEMONICS


@needs_plugin
def test_opcode_table_shows_what_each_instruction_does(specification: Specification) -> None:
    _header, *rows = specification.table("Opcode")
    execution = {row[1].split()[0]: row[2] for row in rows if row[0].isdecimal()}

    assert execution["NOP"] == ""
    assert execution["ADD"] == "R[rd] = R[rs1] + R[rs2]"
    assert execution["MUL"] == "R[rd] = (R[rs1] * R[rs2])(15:0)"
    assert execution["LIH"] == "R[rd] = imm ++ R[rd](7:0)"
    assert execution["BZ"] == "if (R[rs] == 0) PC = PC + 2 + 2 * sext(off)"
    assert execution["PUSH"] == "R[sp] = R[sp] - 2 M[R[sp]](15:0) = R[rs]"


@needs_plugin
def test_every_macro_is_expanded(specification: Specification) -> None:
    assert "sail::" not in specification.text
    assert "include::" not in specification.text


@needs_plugin
def test_follows_changes_to_the_model(tmp_path: Path) -> None:
    workspace = Workspace.copy(tmp_path)
    for path, old, new in [
        (
            DATA_MOVEMENT,
            "union clause instruction = NOP : unit",
            "union clause instruction = IDLE : unit",
        ),
        (DATA_MOVEMENT, "encdec = NOP()", "encdec = IDLE()"),
        (DATA_MOVEMENT, "execute(NOP())", "execute(IDLE())"),
        (DATA_MOVEMENT, "Does nothing.", "Waits for a step."),
        (SYNTAX, 'assembly = NOP() <-> "NOP"', 'assembly = IDLE() <-> "IDLE"'),
        (SYNTAX, '"MOV " ^ reg_name(rd) ^ ", "', '"MOV " ^ reg_name(rd) ^ "; "'),
    ]:
        workspace.edit(path, old, new)

    workspace.build("doc", "html")
    specification = Specification.read(workspace.output / HTML)
    opcodes = {row[1].split()[0]: row for row in specification.table("Opcode")}

    assert "Waits for a step." in specification.text
    assert len(specification.listings("insn-IDLE")) == 3
    assert specification.listings("insn-NOP") == []
    assert (opcodes["IDLE"][1], opcodes["MOV"][1]) == ("IDLE", "MOV rd; rs")


@needs_plugin
@pytest.mark.parametrize(
    "edits",
    [
        pytest.param(
            [(SYNTAX, '<-> "NOP"', '<-> "NOP" ^ dec_bits_8(0x00)')],
            id="assembly-prints-a-constant",
        ),
        pytest.param(
            [
                (
                    DATA_MOVEMENT,
                    "mapping clause encdec = NOP() <-> 0b00000 : opcode @ ignored(11)\n",
                    "",
                ),
                (SYNTAX, 'mapping clause assembly = NOP() <-> "NOP"\n', ""),
            ],
            id="instruction-without-clauses",
        ),
        pytest.param(
            [(DATA_MOVEMENT, "HLT() <-> 0b00001", "HLT() <-> 0b00000")],
            id="two-instructions-with-one-encoding",
        ),
        pytest.param(
            [
                (
                    DATA_MOVEMENT,
                    "function clause execute(NOP()) = ()\n",
                    "function clause execute(NOP()) = ()\nfunction clause execute(NOP()) = ()\n",
                )
            ],
            id="clause-hidden-by-an-earlier-one",
        ),
    ],
)
def test_rejects_a_model_it_cannot_tabulate(
    tmp_path: Path, edits: list[tuple[str, str, str]]
) -> None:
    workspace = Workspace.copy(tmp_path)
    for path, old, new in edits:
        workspace.edit(path, old, new)

    run = workspace.just("doc", "metadata")

    assert run.returncode != 0
    assert Path(edits[0][0]).name in run.stdout + run.stderr
    assert not (workspace.output / METADATA).exists()


# Each test instruction set's word width, opcode width (None: no single leading opcode) and
# instructions, with their constructors, syntax and fields.
INSTRUCTION_SET_CASES = [
    pytest.param(
        "tiny",
        12,
        4,
        [
            ("Tiny", "TINY:second/first", ["=0010", "first:2", "second:3", "_:3"]),
            ("Stop", "STOP", ["=0001", "_:8"]),
        ],
        id="12-bit",
    ),
    pytest.param(
        "wide",
        32,
        6,
        [
            ("ADD", "add rd, rs, rt", ["=000001", "rd:5", "rs:5", "rt:5", "_:11"]),
            ("LOAD", "load rd, offset(base)", ["=000010", "rd:5", "base:5", "offset:16"]),
            ("HALT", "halt", ["=111111", "_:26"]),
        ],
        id="32-bit",
    ),
    pytest.param(
        "full",
        4,
        1,
        [("ZERO", "zero", ["=0", "_:3"]), ("ONE", "one value", ["=1", "value:3"])],
        id="every-opcode-assigned",
    ),
    pytest.param(
        "riscish",
        32,
        None,
        [
            (
                "RTYPE",
                "add rd, rs1, rs2",
                ["funct7=0000000", "rs2:5", "rs1:5", "funct3=000", "rd:5", "opcode=0110011"],
            ),
            (
                "RTYPE",
                "sub rd, rs1, rs2",
                ["funct7=0100000", "rs2:5", "rs1:5", "funct3=000", "rd:5", "opcode=0110011"],
            ),
            (
                "LW",
                "lw rd, imm(rs1)",
                ["imm:12", "rs1:5", "funct3=010", "rd:5", "opcode=0000011"],
            ),
            (
                "SLLI",
                "slli rd, rs1, shamt",
                ["=000000", "shamt:6", "rs1:5", "funct3=001", "rd:5", "opcode=0010011"],
            ),
        ],
        id="risc-v-like",
    ),
]

# A document for the generated parts alone, with the sections that instructions.adoc nests in.
DOCUMENT = """\
= Instruction set
:sail-doc: {docdir}/tara.json

== Encodings

include::formats.adoc[]

include::opcodes.adoc[]

== Instructions

=== All

include::instructions.adoc[]
"""


def described(field: Field) -> str:
    """A field as `name=bits` if it is fixed, `name:width` if an operand, and `_:width` if
    ignored."""

    match field:
        case Fixed(name=name, bits=bits):
            return f"{name or ''}={bits}"
        case Operand(name=name, width=width):
            return f"{name}:{width}"
        case Ignored(width=width):
            return f"_:{width}"


def install(tmp_path: Path, name: str) -> Workspace:
    """A workspace whose model is the test instruction set `name`, with its sections built."""

    workspace = Workspace.copy(tmp_path)
    workspace.install(INSTRUCTION_SETS / f"{name}.sail")
    workspace.build("doc", "sections")
    return workspace


@needs_plugin
@pytest.mark.parametrize(
    ("name", "word_width", "opcode_width", "instructions"), INSTRUCTION_SET_CASES
)
def test_documents_other_instruction_sets(
    tmp_path: Path,
    name: str,
    word_width: int,
    opcode_width: int | None,
    instructions: list[tuple[str, str, list[str]]],
) -> None:
    workspace = install(tmp_path, name)
    workspace.build("doc", "bundle")
    instruction_set = InstructionSet.read(workspace.output / METADATA)
    document = workspace.output / "document.adoc"
    document.write_text(DOCUMENT)

    assert (instruction_set.word_width, instruction_set.opcode_width) == (word_width, opcode_width)
    assert [
        (i.constructor, i.syntax, list(map(described, i.fields)))
        for i in instruction_set.instructions
    ] == instructions
    rendered = subprocess.run(
        ["asciidoctor", "-r", "asciidoctor-sail", "--failure-level", "WARN", document],
        cwd=workspace.output,
        capture_output=True,
        text=True,
        check=False,
    )
    assert rendered.returncode == 0, rendered.stderr
    specification = Specification.read(workspace.output / "document.html")
    for entry in instruction_set.outline:
        if isinstance(entry, ConstructorEntry):
            assert len(specification.listings(section_anchor(entry.name))) == len(entry.clauses)


@needs_plugin
def test_follows_the_source_order_of_anchors_and_constructors(tmp_path: Path) -> None:
    instruction_set = InstructionSet.read(install(tmp_path, "riscish").output / METADATA)

    assert [(type(entry), entry.name) for entry in instruction_set.outline] == [
        (AnchorEntry, "register_arithmetic"),
        (ConstructorEntry, "RTYPE"),
        (AnchorEntry, "loads"),
        (ConstructorEntry, "LW"),
        (ConstructorEntry, "SLLI"),
    ]
    rtype = instruction_set.outline[1]
    assert isinstance(rtype, ConstructorEntry)
    assert [(c.function, c.selector, c.pattern, c.documented) for c in rtype.clauses] == [
        ("encdec", Selector.LEFT, "RTYPE(_, _, _, RISCV_ADD)", False),
        ("encdec", Selector.LEFT, "RTYPE(_, _, _, RISCV_SUB)", False),
        ("execute", Selector.PATTERN, "RTYPE(_, _, _, RISCV_ADD)", True),
        ("execute", Selector.PATTERN, "RTYPE(_, _, _, RISCV_SUB)", False),
        ("assembly", Selector.LEFT, "RTYPE(_, _, _, _)", False),
    ]


@needs_plugin
def test_writes_the_execution_in_the_model_s_notation(tmp_path: Path) -> None:
    instruction_set = InstructionSet.read(install(tmp_path, "riscish").output / METADATA)

    assert [(i.mnemonic, i.execution, i.condition) for i in instruction_set.instructions] == [
        ("add", ("x[rd] = x[rs1] + x[rs2]",), None),
        ("sub", ("x[rd] = x[rs1] - x[rs2]",), None),
        ("lw", ("address = x[rs1] + sext(imm)", "x[rd] = M[address](31:0)"), None),
        ("slli", ("x[rd] = x[rs1] << shamt",), "shamt[5] == bitzero"),
    ]


@needs_plugin
def test_has_no_unassigned_row_when_every_opcode_is_assigned(tmp_path: Path) -> None:
    opcodes = (install(tmp_path, "full").output / OPCODES).read_text()

    assert "unassigned" not in opcodes


def instruction(opcode: int, *, field: str, condition: str | None = None) -> Instruction:
    """An instruction of an 8-bit instruction set with a 4-bit opcode and one 4-bit field."""

    return Instruction(
        constructor=f"I{opcode}",
        syntax=f"i{opcode} {field}",
        fields=(Fixed(name="opcode", bits=f"{opcode:04b}"), Operand(name=field, width=4)),
        condition=condition,
        execution=(),
    )


def instruction_set(instructions: tuple[Instruction, ...]) -> InstructionSet:
    return InstructionSet(word_width=8, instructions=instructions, outline=())


def test_opcode_table_runs_unassigned_opcodes_together() -> None:
    opcodes = (0, 1, 3, 4, 5, 6, 7, 8, 9, 10)
    table = instruction_set(tuple(instruction(opcode, field="x") for opcode in opcodes))

    first_cells = [row.cells[0].content for row in table.opcode_table(4).rows]

    assert first_cells == [
        (Text(label),) for label in ["0", "1", "2", *map(str, opcodes[2:]), "11-15"]
    ]


def test_tabulates_guarded_encodings_with_their_conditions() -> None:
    guarded = instruction_set(
        (instruction(0, field="x"), instruction(1, field="x", condition="x != 0b0000"))
    )

    assert guarded.opcode_width is None
    assert guarded.opcodes().header == ("Encoding", "Condition", "Syntax", "Execution", "Format")


def test_format_table_merges_a_field_across_formats() -> None:
    table = instruction_set(tuple(instruction(opcode, field=f"f{opcode}") for opcode in range(10)))

    rows = table.format_table().rows
    opcode_cells = [cell for row in rows for cell in row.cells if str(cell).endswith("`+opcode+`")]

    assert [row.cells[0].content[-1] for row in rows] == [
        Text(f"F{number}") for number in range(1, 11)
    ]
    assert [(cell.columns, cell.rows) for cell in opcode_cells] == [(1, 10)]


def test_fits_a_table_to_its_longest_lines() -> None:
    table = Table(
        columns=(Column(), Column()),
        header=("A", "B"),
        rows=(
            Row(cells=(Cell(content=(Code("x" * 10),)), Cell(content=(Code("y" * 20),)))),
            Row(
                cells=(
                    Cell(content=(Code("x" * 5), LineBreak(), Code("x" * 30))),
                    Cell(content=(Code("y" * 2),)),
                )
            ),
            Row(cells=(Cell(content=(Code("z" * 200),), columns=2),)),
        ),
    ).fitted()

    first, second = (column.width or 0 for column in table.columns)
    assert first > second
    assert table.width is not None and table.width < 100
