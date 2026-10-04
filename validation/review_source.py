#!/usr/bin/env python3
"""Restricted source checks, not a Sail parser, typechecker or interpreter.

Only field concatenations are evaluated from source. Other checks are literal
structure checks and separately written finite arithmetic/alias equations.
No passing result from this script means that Sail compiled or ran.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def clean(text: str) -> str:
    return re.sub(r'//[^\n]*', '', re.sub(r'/\*[\s\S]*?\*/', '', text))


def literal(token: str) -> tuple[int, int]:
    require(re.fullmatch(r'0b[01]+|0x[0-9a-fA-F]+', token) is not None,
            f'Unsupported literal: {token}')
    return int(token, 0), (len(token) - 2) * (4 if token.startswith('0x') else 1)


def extract(text: str) -> dict[str, dict[str, Any]]:
    source = clean(text)
    types: dict[str, list[int]] = {}
    for name, typ in re.findall(r'^union clause instruction = ([A-Z]+) : ([^\n]+)', source, re.M):
        require(name not in types, f'Duplicate constructor {name}')
        require(not re.sub(r'regidx|bits\(\d+\)|unit|[(),\s]', '', typ),
                f'Unsupported type for {name}')
        types[name] = [3 if t == 'regidx' else int(t[5:-1])
                       for t in re.findall(r'regidx|bits\(\d+\)', typ)]
    layouts: dict[str, dict[str, Any]] = {}
    for match in re.finditer(
            r'mapping clause encdec_fields\s*=\s*([A-Z]+)\(([^)]*)\)\s*<->\s*\(M_([A-Z]+),\s*([^)]*)\)', source):
        name, args, tag, expression = match.groups()
        require(name == tag and name not in layouts, f'Mnemonic mismatch {name}')
        names = [a.strip() for a in args.split(',') if a.strip()]
        require(len(names) == len(types[name]), f'Arity mismatch {name}')
        widths = dict(zip(names, types[name], strict=True))
        parts = [p.strip() for p in expression.split('@')]
        require(sorted(p for p in parts if p in widths) == sorted(names),
                f'Every operand must appear exactly once: {name}')
        require(sum(widths[p] if p in widths else literal(p)[1] for p in parts) == 11,
                f'Payload width mismatch {name}')
        layouts[name] = {'names': names, 'widths': types[name], 'parts': parts}
    executes = re.findall(r'^function clause execute ([A-Z]+)\(', source, re.M)
    require(len(types) == len(layouts) == len(executes) == 27 and
            set(types) == set(layouts) == set(executes), 'Instruction coverage differs')
    for name in types:
        require(re.search(
            rf'union clause instruction = {name}[^\n]*\s+'
            rf'mapping clause encdec_fields\s*=\s*{name}[^\n]*\s+'
            rf'function clause execute {name}\(', source) is not None,
            f'Type, layout, execution not together for {name}')
    return layouts


def unpack(layout: dict[str, Any], payload: int) -> tuple[int, ...] | None:
    widths = dict(zip(layout['names'], layout['widths'], strict=True))
    values: dict[str, int] = {}
    remaining = 11
    for part in layout['parts']:
        width = widths[part] if part in widths else literal(part)[1]
        remaining -= width
        value = (payload >> remaining) & ((1 << width) - 1)
        if part in widths:
            values[part] = value
        elif value != literal(part)[0]:
            return None
    return tuple(values[n] for n in layout['names'])


def pack(layout: dict[str, Any], args: tuple[int, ...]) -> int:
    variables = dict(zip(layout['names'], zip(args, layout['widths'], strict=True), strict=True))
    result = 0
    for part in layout['parts']:
        if part == 'op':
            continue
        value, width = variables[part] if part in variables else literal(part)
        result = (result << width) | value
    return result


def compare_layouts(text: str, baseline: dict[str, Any]) -> dict[str, int]:
    layouts = extract(text)
    require(set(layouts) == set(baseline['layouts']), 'Changed instruction set')
    counts: dict[str, int] = {}
    for name, current in layouts.items():
        old = baseline['layouts'][name]
        require(current['widths'] == old['widths'], f'Changed operand types {name}')
        count = 0
        for payload in range(2048):
            guard = old['guard']
            canonical = guard is None or (
                (payload >> guard[1]) & ((1 << (guard[0] - guard[1] + 1)) - 1)) == guard[2]
            expected = tuple((payload >> lo) & ((1 << (hi - lo + 1)) - 1)
                             for hi, lo in old['slices']) if canonical else None
            actual = unpack(current, payload)
            require(actual == expected, f'Unpacking/padding changed {name} {payload:03x}')
            if actual is not None:
                require(pack(current, actual) == pack(old, actual) == payload,
                        f'Packing changed {name} {payload:03x}')
                count += 1
        counts[name] = count
    return counts


def structural_checks(text: str, support: str, driver: str, codec: str) -> None:
    instruction_source = clean(text)
    require('Events' not in instruction_source and 'Platform' not in instruction_source,
            'Instruction clauses must not manage observers/platform state')
    require('preflight' not in instruction_source and 's0' not in instruction_source,
            'Old preflight/snapshot plumbing remains')
    require('X(rd) = X(rs1) + X(rs2)' in instruction_source and
            'X(rd) = X(rd) + signed(imm)' in instruction_source, 'Arithmetic spelling changed')
    require(instruction_source.count('nextPC = PC + 0x0002 + 2 * signed(off)') == 4,
            'Relative branch clauses changed')
    require('let addr : word = X(base) + signed(off);' in instruction_source,
            'Effective address expression changed')
    push = instruction_source.split('function clause execute PUSH', 1)[1].split('union clause', 1)[0]
    require('if rs == sp then addr else X(rs)' in push, 'PUSH R7 value changed')
    require(push.index('store_word(addr, value)') < push.index('X(sp) = addr'),
            'PUSH writes SP before a possibly failing store')
    pop = instruction_source.split('function clause execute POP', 1)[1].split('end instruction', 1)[0]
    require(pop.index('load_word(X(sp))') < pop.index('X(rd) = value') < pop.index('X(sp) = X(sp) + 0x0002'),
            'POP ordering changed')
    for name in ('load_word', 'store_word'):
        body = clean(support).split(f'function {name}(', 1)[1].split('}', 1)[0]
        require(body.index('check_word_alignment(addr)') < body.index('bus_'),
                f'{name} performs bus access before alignment check')
    retire = clean(driver).split('function retire(', 1)[1].split('}', 1)[0]
    require(retire.index('nextPC = PC + 0x0002') < retire.index('execute(insn)') < retire.index('PC = nextPC'),
            'PC retirement ordering changed')
    step = clean(driver).split('function step_with(', 1)[1]
    require(step.index('if HALTED') < step.index('if PC[0]') < step.index('check_opcodes(table)') <
            step.index('bus_read_word(PC, Fetch)') < step.index('decode_with(table, raw)') < step.index('retire(insn)'),
            'Fetch/boundary precedence changed')
    require('encdec_fields(insn) => insn' in clean(codec), 'Reverse mapping is not guarded by a pattern')
    for source in (instruction_source, clean(support), clean(driver), clean(codec)):
        require('struct state' not in source and 'struct transition' not in source,
                'Production model contains snapshot/transition plumbing')

    require('shift_left(' not in instruction_source and 'shift_right(' not in instruction_source and
            'mul_low(' not in instruction_source, 'Single-use arithmetic wrappers remain')
    require('get_slice_int(16, product, 0)' in instruction_source and
            instruction_source.count('if amount >= 16 then 0x0000') == 2,
            'Instruction-local arithmetic policy missing')
    require('X(lr) = PC + 0x0002;' in instruction_source,
            'CALL must read its link from architectural PC')
    require('match kind { Fetch => index, Data => 2 + index }' in support,
            'Changed public event flattening convention')
    require('bus_read_word(addr, Data)' in support and
            'bus_write_word(addr, value, Data)' in support,
            'Data word accesses are not named')
    require('bus_read_byte(addr, kind, 0)' in support and
            'bus_read_byte(addr + 0x0001, kind, 1)' in support,
            'Word byte read ordering changed')
    require('bus_write_byte(addr, value[15..8], kind, 0)' in support and
            'bus_write_byte(addr + 0x0001, value[7..0], kind, 1)' in support,
            'Word byte write ordering changed')


def bodies(text: str) -> dict[str, dict[str, Any]]:
    source = clean(text)
    result: dict[str, dict[str, Any]] = {}
    for block in re.split(r"(?=^union clause instruction = )", source, flags=re.M)[1:]:
        block = block.split("end instruction", 1)[0]
        m = re.search(r"function clause execute ([A-Z]+)\(([^)]*)\)\s*=\s*([\s\S]*)", block)
        require(m is not None, "Execution body missing")
        assert m is not None
        name, args, body = m.groups()
        args = [x.strip() for x in args.split(",") if x.strip()]
        body = body.strip()
        if body.startswith("{") and body.endswith("}"):
            body = body[1:-1].strip()
        result[name] = {"args": args, "body": body}
    return result


def compare_bodies(text: str, baseline: dict[str, Any]) -> dict[str, Any]:
    """Exact alpha-renamed source comparison, with seven explicit rewrites.

    This compares text, not Sail meaning. Rewrites are reviewed separately.
    """
    current = bodies(text)
    changes = {"MUL", "SHL", "SHR", "BZ", "BN", "JMP", "CALL"}
    require(current.keys() == baseline.keys(), "Execution coverage changed")
    for name, old in baseline.items():
        new = current[name]
        renames = dict(zip(new["args"], old["args"], strict=True))
        actual = new["body"]
        if renames:
            actual = re.sub(r"\b(" + "|".join(renames) + r")\b",
                            lambda m: renames[m[0]], actual)
        expected = old["body"]
        if name == "MUL":
            expected = ("let product = unsigned(X(a)) * unsigned(X(b)); "
                        "X(d) = get_slice_int(16, product, 0)")
        elif name in ("SHL", "SHR"):
            operation = "sail_shiftleft" if name == "SHL" else "sail_shiftright"
            expected = ("let amount = unsigned(imm); "
                        f"X(d) = if amount >= 16 then 0x0000 else {operation}(X(d), amount)")
        elif name in ("BZ", "BN", "JMP", "CALL"):
            expected = expected.replace("nextPC = nextPC + 2 * signed(off)",
                                        "nextPC = PC + 0x0002 + 2 * signed(off)")
            expected = expected.replace("X(lr) = nextPC;", "X(lr) = PC + 0x0002;")
        require(re.sub(r"\s", "", actual) == re.sub(r"\s", "", expected),
                f"Unreviewed instruction-body edit: {name}")
    return {"alpha_equivalent_source_bodies": 20,
            "explicit_rewrites_checked_as_source": sorted(changes),
            "is_semantic_equivalence_proof": False}


def math_checks() -> dict[str, int]:
    def signed(value: int, width: int) -> int:
        return value if value < 1 << (width - 1) else value - (1 << width)
    bases = (0, 1, 2, 0x0100, 0x7fff, 0x8000, 0xfffe, 0xffff)
    additions = 0
    for width in (5, 8):
        for raw in range(1 << width):
            extended = signed(raw, width) & 65535
            for base in bases:
                require((base + extended) & 65535 == (base + signed(raw, width)) & 65535,
                        'Signed addition identity differs')
                additions += 1
    branches = 0
    for width in (8, 11):
        for raw in range(1 << width):
            old_displacement = signed(raw << 1, width + 1) & 65535
            for pc in bases:
                require((pc + 2 + old_displacement) & 65535 ==
                        (pc + 2 + 2 * signed(raw, width)) & 65535,
                        'Branch displacement identity differs')
                branches += 1
    pushes = 0
    for sp in range(65536):
        address = (sp - 2) & 65535
        for src in range(8):
            old_regs = [0x1111 * r for r in range(8)]
            old_regs[7] = sp
            new_value = address if src == 7 else old_regs[src]
            old_regs[7] = address
            require(new_value == old_regs[src], 'PUSH alias equation differs')
            require(address % 2 == sp % 2, 'PUSH alignment classification differs')
            pushes += 1
    return {'signed_addition_cases_8_bases': additions,
            'branch_cases_8_pcs': branches,
            'push_alias_equation_cases_all_sp_all_src': pushes}


def main() -> None:
    text = (ROOT / 'tara.sail').read_text()
    support = (ROOT / 'machine.sail').read_text()
    driver = (ROOT / 'step.sail').read_text()
    codec = (ROOT / 'encoding.sail').read_text()
    baseline_path = ROOT / 'validation/baseline_layouts.json'
    baseline = json.loads(baseline_path.read_text())
    counts = compare_layouts(text, baseline)
    baseline_bodies = json.loads((ROOT / 'validation/baseline_execution.json').read_text())
    body_review = compare_bodies(text, baseline_bodies['bodies'])
    structural_checks(text, support, driver, codec)
    assignments = {name: int(number) for number, name in
                   re.findall(r'table\[(\d+)\] = Some\(M_([A-Z]+)\);', codec)}
    require(assignments == baseline['evidenced_opcodes'], 'Default opcode evidence changed')
    source_hashes: dict[str, str] = {}
    for path in sorted(ROOT.rglob('*.sail')):
        code = clean(path.read_text())
        require(re.search(r'\b(?:tara_|TARA_|T_[A-Z])[A-Za-z0-9_]*', code) is None,
                f'Architecture-name prefix in {path.name}')
        for include in re.findall(r'\$include "([^"]+)"', code):
            require((path.parent / include).is_file(), f'Broken local include {include}')
        source_hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    tests = (ROOT / 'tests/test_tara.sail').read_text()
    for name in counts:
        require(re.search(rf'\b{name}\(', tests) is not None, f'Test mention absent for {name}')
    require('registers.sail' not in (ROOT / 'Makefile').read_text(), 'Removed adapter referenced by build')
    mutations = {
        'ADD fields swapped': ('M_ADD, rd @ rs1 @ rs2 @ 0b00', 'M_ADD, rd @ rs2 @ rs1 @ 0b00'),
        'ADD padding changed': ('M_ADD, rd @ rs1 @ rs2 @ 0b00', 'M_ADD, rd @ rs1 @ rs2 @ 0b01'),
        'HLT padding changed': ('M_HLT, 0b00000000000', 'M_HLT, 0b00000000001'),
    }
    caught = []
    for label, (before, after) in mutations.items():
        require(text.count(before) == 1, f'Ambiguous mutation {label}')
        try:
            compare_layouts(text.replace(before, after), baseline)
        except ValueError:
            caught.append(label)
        else:
            raise ValueError(f'Missed layout mutation {label}')
    # A separate structural mutation verifies the no-write-before-store check.
    mutated = text.replace('store_word(addr, value);  /* Check/store before changing SP: no rollback. */\n  X(sp) = addr',
                           'X(sp) = addr;\n  store_word(addr, value)')
    require(mutated != text, 'PUSH ordering mutation did not apply')
    try:
        structural_checks(mutated, support, driver, codec)
    except ValueError:
        caught.append('PUSH writes SP before failing store')
    else:
        raise ValueError('Missed PUSH ordering mutation')
    try:
        compare_bodies(text.replace('X(rd) = X(rs1) + X(rs2)',
                                    'X(rd) = X(rs1) - X(rs2)'), baseline_bodies['bodies'])
    except ValueError:
        caught.append('ADD semantic operator changed')
    else:
        raise ValueError('Missed ADD operator mutation')
    result = {
        'status': 'restricted_source_review_passed',
        'sail_parsed_or_typechecked': False,
        'sail_executed': False,
        'native_sail_test_groups_executed': 0,
        'hardware_conformance_checked': False,
        'whole_semantics_equivalence_proved': False,
        'source_sha256': source_hashes,
        'baseline_layout_sha256': hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
        'colocated_instruction_layout_execute_triples': len(counts),
        'tagged_payloads_compared': 27 * 2048,
        'canonical_payloads_all_27': sum(counts.values()),
        'canonical_payloads_evidenced_7': sum(counts[n] for n in assignments),
        'canonical_by_mnemonic': counts,
        'instruction_body_review': body_review,
        'finite_equation_checks_not_sail_runs': math_checks(),
        'mutations_detected': caught,
        'sail_test_groups_authored': len(re.findall(r'^function test_\w+\(', tests, re.M)),
        'production_lines': {p.name: len(p.read_text().splitlines()) for p in sorted(ROOT.glob('*.sail'))},
        'limitations': 'Only restricted field expressions are evaluated from source. Ordering checks match source text; arithmetic and alias checks evaluate separately written equations. No instruction-body execution, Sail type/effect checking, generated-code testing, or equivalence proof is performed.',
    }
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
