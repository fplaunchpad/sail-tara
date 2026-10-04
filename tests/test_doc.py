"""The specification follows the model: each instruction's section shows the model's clauses, the
tables agree with TARA Studio, and the generator reads any instruction set whose encodings start
with a fixed-width opcode."""

import os
import subprocess
from pathlib import Path

import pytest
from src.simulation.cpu import OP_NAME

from helpers.doc import INSTRUCTION_SETS, Bundle, Specification, Workspace
from tara.asciidoc import Text
from tara.doc import (
    OPCODES,
    AnchorEntry,
    Fallback,
    Field,
    Fixed,
    Ignored,
    Instruction,
    InstructionEntry,
    InstructionSet,
    Operand,
    Selector,
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

    assert len(clauses) == 4
    assert specification.listings(f"insn-{mnemonic}") == clauses


@needs_plugin
def test_opcode_table_agrees_with_studio(specification: Specification) -> None:
    _header, *rows = specification.table("Opcode")
    assigned = {int(row[0]): row[3] for row in rows if row[0].isdecimal()}

    assert assigned == OP_NAME
    assert [row[0] for row in rows if not row[0].isdecimal()] == ["27-31"]


@needs_plugin
def test_format_table_lists_each_instruction_once(specification: Specification) -> None:
    _header, *rows = specification.table("Format")

    assert sorted(name for row in rows for name in row[-1].split(", ")) == MNEMONICS


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
        (DATA_MOVEMENT, "encode(NOP())", "encode(IDLE())"),
        (DATA_MOVEMENT, "Some(NOP())", "Some(IDLE())"),
        (DATA_MOVEMENT, "execute(NOP())", "execute(IDLE())"),
        (DATA_MOVEMENT, "Does nothing.", "Waits for a step."),
        (SYNTAX, 'assembly = NOP() <-> "NOP"', 'assembly = IDLE() <-> "IDLE"'),
        (SYNTAX, '"MOV " ^ reg_name(rd) ^ ", "', '"MOV " ^ reg_name(rd) ^ "; "'),
    ]:
        workspace.edit(path, old, new)

    workspace.build("doc", "html")
    specification = Specification.read(workspace.output / HTML)
    opcodes = {row[3]: row for row in specification.table("Opcode")}

    assert "Waits for a step." in specification.text
    assert len(specification.listings("insn-IDLE")) == 4
    assert specification.listings("insn-NOP") == []
    assert (opcodes["IDLE"][4], opcodes["MOV"][4]) == ("IDLE", "MOV rd; rs")


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
                    "union clause instruction = NOP : unit\n",
                    "union clause instruction = NOP : unit\nfunction clause decode(_) = None()\n",
                ),
                ("model/tara.sail", "function clause decode(_) = None()\n", ""),
            ],
            id="fallback-before-the-last-clause",
        ),
        pytest.param(
            [
                (DATA_MOVEMENT, "function clause encode(NOP()) = 0b00000 @ 0b00000000000\n", ""),
                (
                    DATA_MOVEMENT,
                    "function clause decode(0b00000 @ _ : bits(11)) = Some(NOP())\n",
                    "",
                ),
                (SYNTAX, 'mapping clause assembly = NOP() <-> "NOP"\n', ""),
            ],
            id="instruction-without-clauses",
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


# Each test instruction set's word width, opcode width (None: no single leading opcode) and
# instructions, with their syntax and fields.
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
                "ADD",
                "add rd, rs1, rs2",
                ["funct7=0000000", "rs2:5", "rs1:5", "funct3=000", "rd:5", "=0110011"],
            ),
            (
                "SUB",
                "sub rd, rs1, rs2",
                ["funct7=0100000", "rs2:5", "rs1:5", "funct3=000", "rd:5", "=0110011"],
            ),
            ("LW", "lw rd, imm(rs1)", ["imm:12", "rs1:5", "funct3=010", "rd:5", "=0000011"]),
        ],
        id="opcode-in-the-low-bits",
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
    workspace = Workspace.copy(tmp_path)
    workspace.install(INSTRUCTION_SETS / f"{name}.sail")
    workspace.build("doc", "bundle")
    workspace.build("doc", "sections")
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
    for instruction in instruction_set.instructions:
        assert len(specification.listings(instruction.anchor)) == len(instruction.clauses)


@needs_plugin
def test_follows_the_source_order_of_anchors_and_instructions(tmp_path: Path) -> None:
    workspace = Workspace.copy(tmp_path)
    workspace.install(INSTRUCTION_SETS / "riscish.sail")
    workspace.build("doc", "sections")

    instruction_set = InstructionSet.read(workspace.output / METADATA)
    add = next(i for i in instruction_set.instructions if i.constructor == "ADD")

    assert instruction_set.outline == (
        AnchorEntry(name="register_arithmetic"),
        InstructionEntry(name="ADD"),
        InstructionEntry(name="SUB"),
        AnchorEntry(name="loads"),
        InstructionEntry(name="LW"),
    )
    assert [(c.function, c.selector, c.documented) for c in add.clauses] == [
        ("decode", Selector.BODY, False),
        ("semantics", Selector.PATTERN, True),
        ("assembly", Selector.LEFT, False),
    ]


@needs_plugin
def test_leaves_out_the_fallback_when_every_opcode_is_assigned(tmp_path: Path) -> None:
    workspace = Workspace.copy(tmp_path)
    workspace.install(INSTRUCTION_SETS / "full.sail")
    workspace.build("doc", "sections")

    opcodes = (workspace.output / OPCODES).read_text()

    assert "unassigned" not in opcodes
    assert "None" not in opcodes


def instruction(opcode: int, *, field: str) -> Instruction:
    """An instruction of an 8-bit instruction set with a 4-bit opcode and one 4-bit field."""

    return Instruction(
        constructor=f"I{opcode}",
        operand_count=1,
        syntax=f"I{opcode} {field}",
        fields=(Fixed(name=None, bits=f"{opcode:04b}"), Operand(name=field, width=4)),
        clauses=(),
    )


def instruction_set(instructions: tuple[Instruction, ...]) -> InstructionSet:
    return InstructionSet(
        word_width=8,
        instructions=instructions,
        outline=(),
        fallback=Fallback(function="decode", documented=False),
    )


def test_opcode_table_runs_unassigned_opcodes_together() -> None:
    opcodes = (0, 1, 3, 4, 5, 6, 7, 8, 9, 10)
    table = instruction_set(tuple(instruction(opcode, field="x") for opcode in opcodes))

    first_cells = [row.cells[0].content for row in table.opcode_table(4).rows]

    assert first_cells == [
        (Text(label),) for label in ["0", "1", "2", *map(str, opcodes[2:]), "11-15"]
    ]


def test_format_table_merges_a_field_across_formats() -> None:
    table = instruction_set(tuple(instruction(opcode, field=f"f{opcode}") for opcode in range(10)))

    rows = table.format_table().rows
    opcode_cells = [cell for row in rows for cell in row.cells if str(cell).endswith("`+opcode+`")]

    assert [row.cells[0].content[-1] for row in rows] == [
        Text(f"F{number}") for number in range(1, 11)
    ]
    assert [(cell.columns, cell.rows) for cell in opcode_cells] == [(4, 10)]
