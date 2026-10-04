"""The model's disassembler, through `disasm`, against TARA Studio's assembler and opcode
table."""

from itertools import batched

import pytest
from src.assembler.asm import assemble

from tara.emulator import Emulator
from tara.isa import ILLEGAL, MEMORY_BYTES, WORD_BYTES, WORDS, canonical, mnemonic

# Assemble at most a memory's worth of instructions at a time.
BATCH = MEMORY_BYTES // WORD_BYTES


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


def test_emulators_disassemble_alike(emulators: list[Emulator]) -> None:
    if len(emulators) < 2:
        pytest.skip("needs two emulators")

    disassemblies = [emulator.disassembly() for emulator in emulators]
    differing = [word for word in range(WORDS) if len({texts[word] for texts in disassemblies}) > 1]

    assert differing == []
