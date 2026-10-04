"""Stubs for `src.assembler.asm` from the TARA Studio wheel (taracpu 1.2.2)."""

type ListingRow = dict[str, int | str | bool]

class AssemblerError(Exception):
    msg: str
    line: int | None

    def __init__(self, msg: str, line: int | None = None) -> None: ...

def assemble(
    source: str,
) -> tuple[list[tuple[int, int]], list[ListingRow], list[AssemblerError], dict[str, int]]: ...
