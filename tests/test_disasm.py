"""The model's disassembler, through disasm, against TARA Studio's assembler and opcode
table."""

from itertools import batched
from pathlib import Path

import pytest
from src.assembler.asm import assemble

from tara.emulator import Emulator
from tara.isa import ILLEGAL, MEMORY_BYTES, WORD_BYTES, WORDS, canonical, mnemonic

# Assemble at most a memory's worth of instructions at a time.
BATCH = MEMORY_BYTES // WORD_BYTES


def test_lists_every_word_in_order(emulator: Emulator) -> None:
    run = emulator.disasm()

    assert run.status == 0
    assert [line[:5] for line in run.stdout.splitlines()] == [f"{w:04x} " for w in range(WORDS)]


def test_unassigned_opcodes_disassemble_as_illegal(disassembly: tuple[str, ...]) -> None:
    illegal = [word for word, text in enumerate(disassembly) if text == ILLEGAL]

    assert illegal == [word for word in range(WORDS) if mnemonic(word) is None]


def test_disassembly_assembles_to_the_word(disassembly: tuple[str, ...]) -> None:
    """Assembling each line gives back its word, less the bits the format leaves unused."""

    assigned = [word for word in range(WORDS) if mnemonic(word) is not None]
    for words in batched(assigned, BATCH, strict=False):
        placed, _listing, errors, _labels = assemble("\n".join(disassembly[w] for w in words))

        assert errors == []
        assert [word for _address, word in placed] == [canonical(word) for word in words]


def test_c_and_ocaml_disassembly_match(pytestconfig: pytest.Config) -> None:
    emulator_arguments: list[str] = pytestconfig.getoption("--emulator") or []
    by_name = {Path(argument).name: Path(argument) for argument in emulator_arguments}
    c = by_name.get("tara-c")
    ocaml = by_name.get("tara-ocaml")
    if c is None or ocaml is None:
        pytest.skip("the C/OCaml parity check needs both emulators")

    assert Emulator(c).disassembly() == Emulator(ocaml).disassembly()
