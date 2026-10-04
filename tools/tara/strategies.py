"""Hypothesis strategies for TARA programs that always halt, for property-based tests.

A program keeps R7 as a pointer into a data page (0x400, 0x500 or 0x600), well clear of its
code; only PUSH and POP move it, and every other instruction may use any register. Branches and
jumps go forwards and stop at the final HLT. Hypothesis shrinks a failing program towards fewer
instructions and NOPs.
"""

from dataclasses import replace

from hypothesis import strategies as st

from tara.assembly import (
    AddImmediate,
    Bare,
    Branch,
    Immediate,
    Instruction,
    Jump,
    Memory,
    Program,
    Register,
    Stack,
    ThreeRegisters,
    TwoRegisters,
)

MAX_LENGTH = 200
DATA_POINTER = Register.R7
DATA_PAGES = (4, 5, 6)
SKIP_LIMIT = 8

registers = st.sampled_from(Register)
data_registers = st.sampled_from([register for register in Register if register != DATA_POINTER])
offsets = st.integers(min_value=-0x10, max_value=0xF)
skips = st.integers(min_value=0, max_value=SKIP_LIMIT)

# NOP first: Hypothesis shrinks towards the first alternative.
instructions: st.SearchStrategy[Instruction] = st.one_of(
    st.just(Bare(mnemonic=Bare.Mnemonic.NOP)),
    st.builds(
        ThreeRegisters,
        mnemonic=st.sampled_from(ThreeRegisters.Mnemonic),
        rd=data_registers,
        rs1=registers,
        rs2=registers,
    ),
    st.builds(
        TwoRegisters,
        mnemonic=st.sampled_from(TwoRegisters.Mnemonic),
        rd=data_registers,
        rs=registers,
    ),
    st.builds(
        Immediate,
        mnemonic=st.sampled_from(Immediate.Mnemonic),
        rd=data_registers,
        value=st.integers(min_value=0, max_value=0xFF),
    ),
    st.builds(AddImmediate, rd=data_registers, value=st.integers(min_value=-0x80, max_value=0x7F)),
    st.builds(
        Memory,
        mnemonic=st.sampled_from([Memory.Mnemonic.LDW, Memory.Mnemonic.LDB]),
        register=data_registers,
        offset=offsets,
        base=st.just(DATA_POINTER),
    ),
    st.builds(
        Memory,
        mnemonic=st.sampled_from([Memory.Mnemonic.STW, Memory.Mnemonic.STB]),
        register=registers,
        offset=offsets,
        base=st.just(DATA_POINTER),
    ),
    st.builds(Stack, mnemonic=st.just(Stack.Mnemonic.PUSH), register=registers),
    st.builds(Stack, mnemonic=st.just(Stack.Mnemonic.POP), register=data_registers),
    st.builds(Branch, mnemonic=st.sampled_from(Branch.Mnemonic), register=registers, offset=skips),
    st.builds(Jump, mnemonic=st.just(Jump.Mnemonic.JMP), offset=skips),
)


def halting(body: list[Instruction], page: int) -> Program:
    """`body` after setting up the data pointer and before HLT, with every branch and jump cut
    short so that it lands at the HLT at the furthest."""

    prologue = (
        Immediate(mnemonic=Immediate.Mnemonic.LIL, rd=DATA_POINTER, value=0),
        Immediate(mnemonic=Immediate.Mnemonic.LIH, rd=DATA_POINTER, value=page),
    )
    epilogue = (Bare(mnemonic=Bare.Mnemonic.HLT),)
    remaining = range(len(body) - 1, -1, -1)
    return Program((*prologue, *map(forward, body, remaining, strict=True), *epilogue))


def forward(instruction: Instruction, remaining: int) -> Instruction:
    """`instruction`, skipping at most the `remaining` instructions before the final HLT."""

    match instruction:
        case Branch() | Jump() if instruction.offset > remaining:
            return replace(instruction, offset=remaining)
        case _:
            return instruction


programs: st.SearchStrategy[Program] = st.builds(
    halting,
    body=st.lists(instructions, max_size=MAX_LENGTH),
    page=st.sampled_from(DATA_PAGES),
)
