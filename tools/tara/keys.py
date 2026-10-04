"""The input lines, and the key scripts that change them as a run goes on."""

import bisect
import itertools
import random
from dataclasses import dataclass
from enum import STRICT, IntFlag, auto
from typing import Self


class Keys(IntFlag, boundary=STRICT):
    """The input lines that a byte read of the input port returns, from bit 0 (UP) to bit 4."""

    UP = auto()
    DOWN = auto()
    LEFT = auto()
    RIGHT = auto()
    QUIT = auto()


RELEASED = Keys(0)


@dataclass(frozen=True, kw_only=True)
class KeyChange:
    """The input lines from `step` retirements on."""

    step: int
    keys: Keys


@dataclass(frozen=True, kw_only=True)
class KeySchedule:
    """The input lines over a run: `initial` until the first change, then each change's lines.
    The changes' steps increase strictly from 0."""

    initial: Keys = RELEASED
    changes: tuple[KeyChange, ...] = ()

    def __post_init__(self) -> None:
        steps = [change.step for change in self.changes]
        if steps and steps[0] < 0:
            raise ValueError(f"step {steps[0]} is negative")

        for earlier, later in itertools.pairwise(steps):
            if later <= earlier:
                raise ValueError(f"step {later} does not follow step {earlier}")

    @classmethod
    def random(cls, *, seed: str, period: int, until: int) -> Self:
        """Input lines drawn at random every `period` retirements before `until`."""

        rng = random.Random(seed)
        choices = 1 << len(Keys)
        steps = range(0, until, period)
        return cls(
            changes=tuple(KeyChange(step=step, keys=Keys(rng.randrange(choices))) for step in steps)
        )

    def at(self, retirements: int) -> Keys:
        """The input lines for the instruction that follows `retirements` retirements."""

        index = bisect.bisect_right(self.changes, retirements, key=lambda change: change.step)
        return self.changes[index - 1].keys if index else self.initial

    def script(self) -> str:
        """The changes as a key script: a `STEP KEYS` line each."""

        return "".join(f"{change.step} {change.keys}\n" for change in self.changes)
