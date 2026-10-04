"""Input lines, and key scripts that change them as a run goes on."""

import bisect
import itertools
from collections.abc import Sequence
from dataclasses import dataclass
from enum import IntFlag

type KeyChange = tuple[int, int]


class Keys(IntFlag):
    """The input lines that a byte read of the input port returns."""

    UP = 1
    DOWN = 2
    LEFT = 4
    RIGHT = 8
    QUIT = 16


ALL_KEYS = int(Keys.UP | Keys.DOWN | Keys.LEFT | Keys.RIGHT | Keys.QUIT)
HEX_PREFIX = "0x"


def parse_keys(text: str) -> int:
    """Input lines written in decimal or as 0x hex, as `--keys` and key scripts take them."""

    try:
        hexadecimal = text.lower().startswith(HEX_PREFIX)
        keys = int(text, 16) if hexadecimal else int(text, 10)
    except ValueError:
        raise ValueError(f"{text!r}: expected input lines in decimal or 0x hex") from None

    check_keys(keys)
    return keys


def check_keys(keys: int) -> None:
    """Reject values that are not a set of the five input lines."""

    if not 0 <= keys <= ALL_KEYS:
        raise ValueError(f"{keys}: input lines are 0 to {ALL_KEYS}")


def parse_key_script(text: str) -> tuple[KeyChange, ...]:
    """The changes in a key script: `STEP KEYS` lines with strictly increasing steps.

    `;` starts a comment. STEP is a decimal retirement count; KEYS is as `parse_keys` reads it.
    """

    changes: list[KeyChange] = []
    for number, line in enumerate(text.splitlines(), 1):
        match line.partition(";")[0].split():
            case []:
                continue
            case [step, keys] if step.isdecimal():
                changes.append((int(step), parse_keys(keys)))
            case _:
                raise ValueError(f"line {number}: expected STEP KEYS, got {line!r}")

    check_order(changes)
    return tuple(changes)


def check_order(changes: Sequence[KeyChange]) -> None:
    """Reject changes whose steps do not strictly increase from 0."""

    steps = [step for step, _keys in changes]
    if steps and steps[0] < 0:
        raise ValueError(f"step {steps[0]} is negative")

    for earlier, later in itertools.pairwise(steps):
        if later <= earlier:
            raise ValueError(f"step {later} does not follow step {earlier}")


@dataclass(frozen=True, kw_only=True)
class KeySchedule:
    """The input lines over a run: `initial` until the first change, then each change's lines
    from its retirement count on."""

    initial: int = 0
    changes: tuple[KeyChange, ...] = ()

    def __post_init__(self) -> None:
        check_keys(self.initial)
        for _step, keys in self.changes:
            check_keys(keys)

        check_order(self.changes)

    def at(self, retirements: int) -> int:
        """The input lines for the instruction that follows `retirements` retirements."""

        index = bisect.bisect_right(self.changes, retirements, key=lambda change: change[0])
        return self.changes[index - 1][1] if index else self.initial

    def script(self) -> str:
        """The key script of the changes; the initial lines are `--keys`."""

        return "".join(f"{step} {keys}\n" for step, keys in self.changes)
