"""The typeset specification: its opcode table against TARA Studio's, which the emulators'
disassembly is checked against too (test_disasm.py)."""

import re
from pathlib import Path

from src.simulation.cpu import FMT, OP_NAME

DOCUMENT = Path(__file__).parents[1] / "doc" / "tara.tex"
# \defop{opcode}{hex}{bits}{mnemonic}{format}{syntax}; LaTeX checks that the forms agree.
OPCODE_ROW = re.compile(
    r"\\defop\{(?P<opcode>\d+)\}\{[0-9A-F]{2}\}\{[01]{5}\}\{(?P<mnemonic>[A-Z]+)\}\{(?P<format>F\d)\}"
)


def test_opcode_table_lists_every_opcode_with_its_format() -> None:
    rows = OPCODE_ROW.finditer(DOCUMENT.read_text(encoding="utf-8"))
    documented = {int(row["opcode"]): (row["mnemonic"], row["format"]) for row in rows}

    assert documented == {opcode: (name, FMT[name]) for opcode, name in OP_NAME.items()}
