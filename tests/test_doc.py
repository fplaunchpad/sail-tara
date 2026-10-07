"""The readable reference follows the model, and evaluated examples agree
with the independent reference emulator. Generic instruction sets remain supported."""

import os
import subprocess
from pathlib import Path
from xml.etree import ElementTree as XML

import pytest
from src.assembler.asm import assemble
from src.simulation.cpu import OP_NAME

from helpers.doc import INSTRUCTION_SETS, Specification, Workspace
from tara.asciidoc import Text
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
)
from tara.reference import Reference, Step

needs_plugin = pytest.mark.skipif(
    "TARA_DOC_PLUGIN" not in os.environ, reason="needs the Sail plugin in tools/sail-doc"
)
MNEMONICS = sorted(OP_NAME.values())
HTML = "tara.html"
METADATA = "tables.json"
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
def test_opcode_and_instruction_operations_use_the_same_notation(
    specification: Specification, mnemonic: str
) -> None:
    _header, *rows = specification.table("Opcode")
    execution = next(row[2] for row in rows if row[1].split()[0] == mnemonic)
    assert specification.listings(f"insn-{mnemonic}") == [execution]


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
def test_opcode_table_uses_compact_symbolic_operations(specification: Specification) -> None:
    header, *rows = specification.table("Opcode")
    execution = {row[1].split()[0]: row[2] for row in rows if row[0].isdecimal()}

    assert header == ["Opcode", "Syntax", "Execution", "Format"]
    assert execution["NOP"] == "—"
    assert execution["ADD"] == "R[rd] = R[rs1] + R[rs2]"
    assert execution["MUL"] == "R[rd] = (R[rs1] * R[rs2])[15:0]"
    assert execution["LIL"] == "R[rd] = zext16(imm)"
    assert execution["LIH"] == "R[rd] = imm ++ R[rd][7:0]"
    assert execution["LDW"] == "R[rd] = M[R[base] + s(off)][15:0]"
    assert execution["STB"] == "M[R[base] + s(off)][7:0] = R[rs][7:0]"
    assert execution["SHR"] == "R[rd] = R[rd] >> shamt[4:0]"
    assert execution["SLT"] == "R[rd] = s(R[rs1]) < s(R[rs2]) ? 1 : 0"
    assert execution["BZ"] == "if (R[rs] == 0) { PC_next = PC + 2 + 2 * s(off) }"
    assert execution["PUSH"] == "R[sp] = R[sp] - 2 M[R[sp]][15:0] = R[rs]"
    assert execution["POP"] == "R[rd] = M[R[sp]][15:0] R[sp] = R[sp] + 2"
    assert "wrap16" not in " ".join(execution.values())


@needs_plugin
def test_every_macro_is_expanded(specification: Specification) -> None:
    assert "sail::" not in specification.text
    assert "include::" not in specification.text


@needs_plugin
def test_reference_omits_source_listings_and_repeated_labels(
    built: Workspace, specification: Specification
) -> None:
    assert not (built.output / "formal.adoc").exists()
    assert "Formal Sail definition" not in specification.text
    assert "Helpers:" not in specification.text
    assert "Uses:" not in specification.text
    assert "Used by:" not in specification.text
    assert "· encoding" not in specification.text
    assert "This includes the shared" not in specification.text
    assert "Worked examples" not in specification.text
    assert "Initial state:" not in specification.text
    assert "instruction-example" not in (built.output / HTML).read_text()
    assert not any(
        (element.attributes.get("id") or "").startswith("source-")
        or element.attributes.get("class") == "language-sail"
        for element in specification.document.elements()
    )


def literal(value: str) -> int | bool:
    if value in {"false", "true"}:
        return value == "true"

    return int(value, 0)


def reference_state(cpu: Reference) -> dict[str, int | bool]:
    return {
        "PC": cpu.pc,
        "HALTED": cpu.halted,
        "KEYS": cpu.keys,
        **{f"R{index}": value for index, value in enumerate(cpu.reg)},
        **{f"M[0x{index:03X}]": value for index, value in enumerate(cpu.mem)},
    }


@needs_plugin
@pytest.mark.parametrize("mnemonic", MNEMONICS)
def test_worked_examples_agree_with_assembler_and_reference(
    built: Workspace, mnemonic: str
) -> None:
    instruction_set = InstructionSet.read(built.output / METADATA)
    instruction = next(i for i in instruction_set.instructions if i.mnemonic == mnemonic)
    assert instruction.examples
    for example in instruction.examples:
        assert len({(state.register, state.index) for state in example.setup}) == len(example.setup)
        placed, _listing, errors, _labels = assemble(example.assembly)
        assert errors == []
        assert [word for _address, word in placed] == [literal(example.word)]
        cpu = Reference(b"")
        for state in example.setup:
            value = literal(state.value)
            match state.register:
                case "PC":
                    cpu.pc = int(value)
                case "GPR":
                    assert state.index is not None
                    cpu.reg[state.index] = int(value)
                case "MEM":
                    assert state.index is not None
                    cpu.mem[state.index] = int(value)
                case "HALTED":
                    cpu.halted = bool(value)
                case "KEYS":
                    cpu.keys = int(value)
                case _:
                    raise AssertionError(f"unsupported reference setup: {state.register}")

        # The reference fetches; examples run decoded instructions. Put the same word at PC
        # before taking the reference snapshot, so unchanged instruction bytes aren't effects.
        cpu.write_word(cpu.pc, int(literal(example.word)))
        before = reference_state(cpu)
        cpu.keys = int(literal(example.arguments[0]))
        assert cpu.advance() == Step.RETIRED
        assert example.retirement == "Retired(())"
        after = reference_state(cpu)
        observed = {row.name for row in example.observations}
        assert {name for name in before if before[name] != after[name]} <= observed
        for row in example.observations:
            assert literal(row.before) == before[row.name], (example.title, row.name)
            assert literal(row.after) == after[row.name], (example.title, row.name)


@needs_plugin
def test_encoding_diagrams_have_exact_proportions_and_accessible_descriptions(
    built: Workspace,
) -> None:
    instruction_set = InstructionSet.read(built.output / METADATA)
    namespace = {"svg": "http://www.w3.org/2000/svg"}
    for instruction, anchor in instruction_set.anchor_of.items():
        svg = XML.parse(built.output / "encodings" / f"{anchor}.svg").getroot()
        rectangles = svg.findall("svg:rect", namespace)
        assert len(rectangles) == len(instruction.fields)
        assert [float(rect.attrib["width"]) for rect in rectangles] == pytest.approx(
            [960 * field.width / instruction_set.word_width for field in instruction.fields]
        )
        assert float(rectangles[-1].attrib["x"]) + float(rectangles[-1].attrib["width"]) == 972
        description = svg.find("svg:desc", namespace)
        assert description is not None and description.text is not None
        assert "bits 15:" in description.text
        assert svg.attrib["aria-labelledby"] == f"{anchor}-title {anchor}-description"


@needs_plugin
def test_reference_links_resolve_and_helper_semantics_are_present(
    specification: Specification,
) -> None:
    elements = list(specification.document.elements())
    ids = [element.attributes["id"] for element in elements if "id" in element.attributes]
    assert len(ids) == len(set(ids))
    links = [element.attributes.get("href") for element in elements if element.tag == "a"]
    assert all(link[1:] in ids for link in links if link and link.startswith("#"))
    assert "helper-sign_extend_16" in ids
    assert "0x80 becomes 0xFF80" in specification.text
    assert "Signed interpretation returns an integer" in specification.text
    assert "helper-read_word" in ids
    assert "Decode / parse: _ when false" in specification.text
    assert specification.listings("insn-LDW") == ["R[rd] = M[R[base] + s(off)][15:0]"]
    assert specification.listings("instruction-retirement") == [
        "PC_next = PC + 2 execute(insn) PC = pc_mask(PC_next) Retired"
    ]


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
    assert len(specification.listings("insn-IDLE")) == 1
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


@needs_plugin
@pytest.mark.parametrize(
    ("path", "old", "new", "diagnostic"),
    [
        (DATA_MOVEMENT, 'title = "No operation"', 'title = ""', "requires a title"),
        (DATA_MOVEMENT, 'value = "0x1234"', 'value = "read_word(PC)"', "must be literals"),
        (DATA_MOVEMENT, 'value = "0x1234"', 'value = "0b1"', "invalid documentation example"),
        (DATA_MOVEMENT, "watch = [R1, R2]", "watch = [R99]", "unknown example observation"),
        ("model/tara.sail", 'label = "R{index}"', 'label = ""', "known registers and labels"),
        (DATA_MOVEMENT, "related = [LIH]", "related = [MISSING]", "unknown or ambiguous"),
    ],
)
def test_rejects_invalid_documentation_inputs(
    tmp_path: Path, path: str, old: str, new: str, diagnostic: str
) -> None:
    workspace = Workspace.copy(tmp_path)
    workspace.edit(path, old, new)
    run = workspace.just("doc", "sections")
    assert run.returncode != 0
    assert diagnostic in run.stdout + run.stderr
    assert "Traceback" not in run.stdout + run.stderr


@needs_plugin
def test_discovers_new_helper_dependencies_without_a_layout_edit(tmp_path: Path) -> None:
    workspace = Workspace.copy(tmp_path)
    workspace.edit(
        "model/machine.sail",
        "/*!\nKeeps the low 11 bits of a PC value",
        "function doc_identity(value : word) -> word = value\n\n/*!\nKeeps the low 11 bits of a PC value",
    )
    workspace.edit(
        "model/machine.sail",
        "function pc_mask(value : word) -> word = 0b00000 @ value[10 .. 0]",
        "function pc_mask(value : word) -> word = doc_identity(0b00000 @ value[10 .. 0])",
    )
    workspace.build("doc", "sections")
    instruction_set = InstructionSet.read(workspace.output / METADATA)
    helper = next(helper for helper in instruction_set.helpers if helper.name == "doc_identity")
    assert helper.signature == "bitvector(16) -> bitvector(16)"
    assert helper.dependencies == ()
    assert "[#helper-doc_identity]" in (workspace.output / "helpers.adoc").read_text()


@needs_plugin
def test_guarded_execute_preserves_order_and_fallback(tmp_path: Path) -> None:
    workspace = Workspace.copy(tmp_path)
    workspace.edit(
        DATA_MOVEMENT,
        "function clause execute(NOP()) = ()",
        "function clause execute(NOP() if PC == 0x0100) = X(0b001) = 0x0005\n"
        "function clause execute(NOP()) = X(0b001) = 0x0007",
    )
    workspace.build("doc", "sections")
    instruction_set = InstructionSet.read(workspace.output / METADATA)
    nop = next(
        instruction for instruction in instruction_set.instructions if instruction.mnemonic == "NOP"
    )
    assert nop.operation.lines == [
        "if PC == 0x0100:",
        "  R[0b001] <- 0x0005",
        "else:",
        "  R[0b001] <- 0x0007",
    ]
    assert nop.operation.card_lines == ["if (PC == 256) { R[1] = 5 } else { R[1] = 7 }"]


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

include::helpers.adoc[]

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
    for anchor in instruction_set.anchor_of.values():
        assert len(specification.listings(anchor)) == 1


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

    assert [
        (i.mnemonic, tuple(i.operation.lines), i.condition) for i in instruction_set.instructions
    ] == [
        ("add", ("x[rd] <- wrap32(x[rs1] + x[rs2])",), None),
        ("sub", ("x[rd] <- wrap32(x[rs1] - x[rs2])",), None),
        (
            "lw",
            ("let address = wrap32(x[rs1] + sign_extend_32(imm))", "x[rd] <- M[address][31:0]"),
            None,
        ),
        ("slli", ("x[rd] <- x[rs1] << unsigned6(shamt)",), "shamt[5] == bitzero"),
    ]


@needs_plugin
def test_encoding_constraints_keep_different_guards_on_both_sides(tmp_path: Path) -> None:
    workspace = install(tmp_path, "riscish")
    workspace.edit(
        "model/syntax.sail",
        "opcode if shamt[5] == bitzero",
        "opcode if shamt[4] == bitzero",
    )
    workspace.build("doc", "sections")
    instruction_set = InstructionSet.read(workspace.output / METADATA)
    slli = next(
        instruction
        for instruction in instruction_set.instructions
        if instruction.mnemonic == "slli"
    )
    assert slli.condition == "(shamt[4] == bitzero) && (shamt[5] == bitzero)"


@needs_plugin
def test_execution_renaming_preserves_operands_and_local_scope(tmp_path: Path) -> None:
    workspace = install(tmp_path, "riscish")
    workspace.edit(
        "model/syntax.sail",
        "function clause execute(LW(imm, rs1, rd)) = {\n"
        "  let address = X(rs1) + sail_sign_extend(imm, 32);\n"
        "  set_X(rd, load(address))\n}",
        "function clause execute(LW(displacement, input, output)) = {\n"
        "  let rd = X(input) + sail_sign_extend(displacement, 32);\n"
        "  set_X(output, load(rd))\n}",
    )
    workspace.build("doc", "sections")
    instruction_set = InstructionSet.read(workspace.output / METADATA)
    lw = next(
        instruction for instruction in instruction_set.instructions if instruction.mnemonic == "lw"
    )
    assert lw.operation.lines == [
        "let local_rd = wrap32(x[rs1] + sign_extend_32(imm))",
        "x[rd] <- M[local_rd][31:0]",
    ]
    assert lw.operation.card_lines == [
        "local_rd = x[rs1] + sext32(imm)",
        "x[rd] = M[local_rd][31:0]",
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
