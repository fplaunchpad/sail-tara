/* Sail-native regression suite for the TARA model.
 * Expected values follow the website's RTL description (see README.md).
 * Assertions are test failures, not TARA traps.
 */

$include "harness.sail"

let no_keys : bits(5) = 0b00000

val expect_retired : transition -> state
function expect_retired(t) = {
    match t.result {
        Retired() => (),
        _ => assert(false, "expected the instruction to retire"),
    };
    t.state
}

val run_one : (state, instruction) -> state
function run_one(s, insn) = expect_retired(execute_from(no_keys, s, insn))

val step_one : state -> state
function step_one(s) = expect_retired(step_from(no_keys, s))

val expect_register : (state, instruction, regidx, word) -> unit
function expect_register(s, insn, r, expected) = {
    let result = run_one(s, insn);
    assert(result.regs[unsigned(r)] == expected, "wrong register result")
}

val expect_same_memory : (state, state) -> unit
function expect_same_memory(a, b) = {
    foreach (p from 0 to 2047) {
        assert(a.mem[p] == b.mem[p], "memory differs")
    }
}

val expect_same_state : (state, state) -> unit
function expect_same_state(a, b) = {
    assert(a.pc == b.pc, "PC differs");
    assert(a.halted == b.halted, "halt latch differs");
    foreach (r from 0 to 7) {
        assert(a.regs[r] == b.regs[r], "register differs")
    };
    expect_same_memory(a, b)
}

val seed_state : unit -> state
function seed_state() = {
    var s : state = zero_state();
    s.pc = 0x0100;
    s.regs[0] = 0xAAAA;
    s.regs[1] = 0x8001;
    s.regs[2] = 0x0002;
    s.regs[3] = 0x1234;
    s.regs[4] = 0x0400;
    s.regs[5] = 0x0000;
    s.regs[6] = 0x0120;
    s.regs[7] = 0x0500;
    s.mem[1024] = 0xAB;
    s.mem[1025] = 0xCD;
    s.mem[1280] = 0x12;
    s.mem[1281] = 0x34;
    s
}

val test_all_mnemonics : unit -> unit
function test_all_mnemonics() = {
    let s = seed_state();
    expect_same_state(run_one(s, NOP()), { s with pc = 0x0102 });
    expect_same_state(run_one(s, HLT()), { s with pc = 0x0102,  halted = true });

    expect_register(s, MOV(0b000, 0b011), 0b000, 0x1234);
    expect_register(s, LIL(0b000, 0xEF), 0b000, 0x00EF);
    expect_register(s, LIH(0b000, 0xEF), 0b000, 0xEFAA);
    expect_register(s, LDW(0b000, 0b100, 0b00000), 0b000, 0xABCD);
    expect_register(s, LDB(0b000, 0b100, 0b00001), 0b000, 0x00CD);
    let sw = run_one(s, STW(0b011, 0b100, 0b00000));
    assert(sw.mem[1024] == 0x12 & sw.mem[1025] == 0x34, "STW stores big-endian");
    let sb = run_one(s, STB(0b011, 0b100, 0b00001));
    assert(sb.mem[1024] == 0xAB & sb.mem[1025] == 0x34, "STB stores the low byte");

    expect_register(s, ADD(0b000, 0b001, 0b010), 0b000, 0x8003);
    expect_register(s, SUB(0b000, 0b001, 0b010), 0b000, 0x7FFF);
    expect_register(s, ADDI(0b000, 0xFF), 0b000, 0xAAA9);
    expect_register(s, MUL(0b000, 0b001, 0b010), 0b000, 0x0002);
    expect_register(s, AND(0b000, 0b000, 0b011), 0b000, 0x0220);
    expect_register(s, OR(0b000, 0b000, 0b011), 0b000, 0xBABE);
    expect_register(s, XOR(0b000, 0b000, 0b011), 0b000, 0xB89E);
    expect_register(s, NOT(0b000, 0b011), 0b000, 0xEDCB);
    expect_register(s, SHL(0b001, 0x01), 0b001, 0x0002);
    expect_register(s, SHR(0b001, 0x01), 0b001, 0x4000);
    expect_register(s, SLT(0b000, 0b001, 0b010), 0b000, 0x0001);
    expect_register(s, SLT(0b000, 0b010, 0b001), 0b000, 0x0000);

    assert(run_one(s, BZ(0b101, 0xFF)).pc == 0x0100, "BZ taken");
    assert(run_one(s, BZ(0b010, 0xFF)).pc == 0x0102, "BZ not taken");
    assert(run_one(s, BN(0b001, 0xFF)).pc == 0x0100, "BN taken");
    assert(run_one(s, BN(0b010, 0xFF)).pc == 0x0102, "BN not taken");
    assert(run_one(s, JMP(0b11111111111)).pc == 0x0100, "JMP");
    let call = run_one(s, CALL(0b00000000011));
    assert(call.pc == 0x0108 & call.regs[6] == 0x0102, "CALL target and link");
    assert(call.regs[7] == s.regs[7], "CALL does not push");
    expect_same_memory(call, s);
    assert(run_one(s, RET()).pc == 0x0120, "RET");
    let push = run_one(s, PUSH(0b011));
    assert(push.regs[7] == 0x04FE & push.mem[1278] == 0x12 & push.mem[1279] == 0x34, "PUSH");
    let pop = run_one(s, POP(0b000));
    assert(pop.regs[0] == 0x1234 & pop.regs[7] == 0x0502, "POP")
}

/* Sources are read before the destination is written; R7 aliases follow the
 * ISA table's sequential wording. */
val test_aliases : unit -> unit
function test_aliases() = {
    let s = seed_state();
    expect_register(s, ADD(0b001, 0b001, 0b001), 0b001, 0x0002);
    expect_register(s, LDW(0b100, 0b100, 0b00000), 0b100, 0xABCD);
    let sw = run_one(s, STW(0b100, 0b100, 0b00000));
    assert(sw.mem[1024] == 0x04 & sw.mem[1025] == 0x00, "STW stores its own base");
    let push = run_one(s, PUSH(0b111));
    assert(
        push.regs[7] == 0x04FE & push.mem[1278] == 0x04 & push.mem[1279] == 0xFE,
        "PUSH R7 stores the decremented SP"
    );
    let pop = run_one(s, POP(0b111));
    assert(pop.regs[7] == 0x1236, "POP R7 increments the loaded value")
}

val test_wrapping : unit -> unit
function test_wrapping() = {
    var s : state = zero_state();
    s.regs[0] = 0xFFFF;
    s.regs[1] = 0x0001;
    s.regs[3] = 0x00AB;
    expect_register(s, ADD(0b000, 0b000, 0b001), 0b000, 0x0000);
    expect_register(s, ADDI(0b001, 0x80), 0b001, 0xFF81);
    let below_zero = run_one(s, STB(0b011, 0b100, 0b11111));
    assert(below_zero.mem[2047] == 0xAB, "byte address 0 - 1 is 0x7FF");
    s.regs[4] = 0xF802;
    let alias = run_one(s, STB(0b011, 0b100, 0b00000));
    assert(alias.mem[2] == 0xAB, "address bits above bit 10 are ignored")
}

/* "PC 16-bit, +2 per fetch, masked to 0x7FF"; CALL links that masked PC. */
val test_pc_rules : unit -> unit
function test_pc_rules() = {
    let s = zero_state();
    assert(run_one({ s with pc = 0x07FE }, NOP()).pc == 0x0000, "PC wraps after 0x7FE");
    let call = run_one({ s with pc = 0x07FE }, CALL(0b00000000010));
    assert(call.regs[6] == 0x0000 & call.pc == 0x0004, "CALL links the masked PC");
    var r : state = s;
    r.regs[6] = 0xF123;
    assert(run_one(r, RET()).pc == 0x0123, "RET keeps 11 bits");
    assert(run_one(s, BZ(0b000, 0xFE)).pc == 0x07FE, "a branch below 0 wraps");
    let base = { s with pc = 0x0100 };
    assert(run_one(base, BZ(0b000, 0x80)).pc == 0x0002, "BZ lowest offset");
    assert(run_one(base, BZ(0b000, 0x7F)).pc == 0x0200, "BZ highest offset");
    let far = { s with pc = 0x0400 };
    assert(run_one(far, JMP(0b10000000000)).pc == 0x0402, "JMP lowest offset wraps");
    assert(run_one(far, JMP(0b01111111111)).pc == 0x0400, "JMP highest offset wraps")
}

/* "word index = addr >> 1": word accesses ignore address bit 0. */
val test_word_alignment : unit -> unit
function test_word_alignment() = {
    var s = seed_state();
    s.regs[4] = 0x0401;
    expect_register(s, LDW(0b000, 0b100, 0b00000), 0b000, 0xABCD);
    expect_register(s, LDB(0b000, 0b100, 0b00000), 0b000, 0x00CD);
    let sw = run_one(s, STW(0b011, 0b100, 0b00000));
    assert(sw.mem[1024] == 0x12 & sw.mem[1025] == 0x34, "odd STW writes the aligned word");

    s.regs[3] = 0x5678;
    s.regs[7] = 0x0503;
    let push = run_one(s, PUSH(0b011));
    assert(push.regs[7] == 0x0501 & push.mem[1280] == 0x56 & push.mem[1281] == 0x78, "odd PUSH");
    s.regs[7] = 0x0501;
    let pop = run_one(s, POP(0b000));
    assert(pop.regs[0] == 0x1234 & pop.regs[7] == 0x0503, "odd POP");

    s.regs[4] = 0x07FF;
    s.mem[2046] = 0x9A;
    s.mem[2047] = 0xBC;
    expect_register(s, LDW(0b000, 0b100, 0b00000), 0b000, 0x9ABC);

    var odd : state = zero_state();
    odd = seed_word(odd, 0x0100, 0x1B07); /* LIL R3, 7 */
    odd.pc = 0x0101;
    let fetched = step_one(odd);
    assert(fetched.regs[3] == 0x0007 & fetched.pc == 0x0103, "an odd PC fetches the aligned word")
}

/* "shamt = imm8[4:0]"; counts 16 to 31 shift every bit out. */
val test_shift_count : unit -> unit
function test_shift_count() = {
    var s : state = zero_state();
    s.regs[1] = 0x0081;
    expect_register(s, SHL(0b001, 0x21), 0b001, 0x0102);
    expect_register(s, SHL(0b001, 0x10), 0b001, 0x0000);
    expect_register(s, SHL(0b001, 0x20), 0b001, 0x0081);
    expect_register(s, SHR(0b001, 0x21), 0b001, 0x0040);
    expect_register(s, SHR(0b001, 0x3F), 0b001, 0x0000)
}

val test_arithmetic_ranges : unit -> unit
function test_arithmetic_ranges() = {
    install_state(zero_state());

    /* Every shift field on 16 evenly spaced words, through SHL and SHR. */
    foreach (sample from 0 to 15) {
        let x : word = get_slice_int(16, sample * 4369, 0);
        foreach (field from 0 to 255) {
            let count = unsigned(get_slice_int(5, field, 0));
            let left : word = if count >= 16 then {
                    0x0000
                } else {
                    get_slice_int(16, unsigned(x) * pow2(count), 0)
                };
            let right : word = if count >= 16 then {
                    0x0000
                } else {
                    get_slice_int(16, tdiv_int(unsigned(x), pow2(count)), 0)
                };
            X(0b000) = x;
            let _ = run_instruction(no_keys, SHL(0b000, get_slice_int(8, field, 0)));
            assert(X(0b000) == left, "SHL");
            X(0b000) = x;
            let _ = run_instruction(no_keys, SHR(0b000, get_slice_int(8, field, 0)));
            assert(X(0b000) == right, "SHR")
        }
    };

    /* Every 16-bit multiplicand, including destination/source aliasing. */
    X(0b001) = 0xAAAB;
    foreach (j from 0 to 65535) {
        X(0b000) = get_slice_int(16, j, 0);
        let _ = run_instruction(no_keys, MUL(0b000, 0b000, 0b001));
        assert(X(0b000) == get_slice_int(16, j * 43691, 0), "MUL keeps the low 16 bits")
    }
}

/* All 65536 words: 27 assigned opcodes decode with any padding; encode emits
 * the canonical (zero-padded) word. */
val test_codec : unit -> unit
function test_codec() = {
    var decodable : int = 0;
    var canonical : int = 0;
    foreach (j from 0 to 65535) {
        let raw : word = get_slice_int(16, j, 0);
        match decode(raw) {
            Some(insn) => {
                decodable = decodable + 1;
                let word = encode(insn);
                assert(word[15 .. 11] == raw[15 .. 11], "encode keeps the opcode");
                if word == raw then {
                    canonical = canonical + 1
                };
                match decode(word) {
                    Some(again) => assert(encode(again) == word, "decode/encode round trip"),
                    None() => assert(false, "canonical word must decode"),
                }
            },
            None() => assert(unsigned(raw[15 .. 11]) >= 27, "only opcodes 27-31 are unassigned"),
        }
    };
    assert(decodable == 55296, "27 opcodes x 2048 payloads decode");
    assert(canonical == 30355, "canonical encoding count");
    match decode(0x4C4C) {
        Some(ADD(d, a, b)) => assert(d == 0b100 & a == 0b010 & b == 0b011, "ADD fields"),
        _ => assert(false, "0x4C4C is ADD R4, R2, R3"),
    };
    match decode(0x4C4F) {
        Some(ADD(d, a, b)) => assert(d == 0b100 & a == 0b010 & b == 0b011, "padding ignored"),
        _ => assert(false, "padding must not change the instruction"),
    };
    match decode(0x0801) {
        Some(HLT()) => (),
        _ => assert(false, "0x0801 is HLT with nonzero padding"),
    };
    assert(encode(HLT()) == 0x0800, "HLT encoding");
    assert(encode(POP(0b011)) == 0xD300, "POP encoding")
}

/* The shared fetch steps (T0-T2) still run, so PC advances; nothing else changes. */
val test_illegal : unit -> unit
function test_illegal() = {
    foreach (op from 27 to 31) {
        let opcode : bits(5) = get_slice_int(5, op, 0);
        let s = seed_word({ zero_state() with pc = 0x07FE }, 0x07FE, opcode @ 0b10101010101);
        let t = step_from(no_keys, s);
        match t.result {
            Illegal(raw) => assert(raw == opcode @ 0b10101010101, "Illegal reports the word"),
            _ => assert(false, "an unassigned opcode must not retire"),
        };
        expect_same_state(t.state, { s with pc = 0x0000 })
    }
}

val test_halt_and_reset : unit -> unit
function test_halt_and_reset() = {
    var s = seed_state();
    s = seed_word(s, 0x0100, 0x0800); /* HLT */
    let halted = step_one(s);
    assert(halted.halted & halted.pc == 0x0102, "HLT retires, then halts");
    let again = step_from(no_keys, halted);
    match again.result {
        Stopped() => (),
        _ => assert(false, "a halted CPU does not fetch"),
    };
    expect_same_state(again.state, halted);
    let decoded = execute_from(no_keys, halted, NOP());
    match decoded.result {
        Stopped() => (),
        _ => assert(false, "a halted CPU does not execute"),
    };
    install_state(halted);
    reset();
    let restarted = snapshot();
    assert(restarted.pc == 0x0000 & not_bool(restarted.halted), "reset restarts at PC 0");
    expect_same_state({ restarted with pc = halted.pc,  halted = true }, halted)
}

/* The hardware manual's Fibonacci words and final state. */
val test_fibonacci : unit -> unit
function test_fibonacci() = {
    var s : state = zero_state();
    s = seed_word(s, 0x0000, 0x1A00);
    s = seed_word(s, 0x0002, 0x1B01);
    s = seed_word(s, 0x0004, 0x1D0A);
    s = seed_word(s, 0x0006, 0xA505);
    s = seed_word(s, 0x0008, 0x4C4C);
    s = seed_word(s, 0x000A, 0x1260);
    s = seed_word(s, 0x000C, 0x1380);
    s = seed_word(s, 0x000E, 0x5DFF);
    s = seed_word(s, 0x0010, 0xB7FA);
    s = seed_word(s, 0x0012, 0x1640);
    s = seed_word(s, 0x0014, 0x0800);
    foreach (i from 1 to 66) {
        s = step_one(s)
    };
    assert(s.halted & s.pc == 0x0016, "Fibonacci halts after HLT at 0x014");
    assert(s.regs[2] == 0x0037 & s.regs[3] == 0x0059 & s.regs[4] == 0x0059, "F(10), F(11)");
    assert(s.regs[5] == 0x0000 & s.regs[6] == 0x0037, "counter and result")
}

val test_live_fetch : unit -> unit
function test_live_fetch() = {
    var s : state = zero_state();
    s = seed_word(s, 0x0002, 0x1A07); /* LIL R2, 7, overwritten before it runs */
    s.regs[0] = 0xF802; /* aliases byte 2 */
    s.regs[1] = 0x0800; /* HLT */
    s = run_one(s, STW(0b001, 0b000, 0b00000));
    let patched = step_one(s);
    assert(
        patched.halted & patched.pc == 0x0004 & patched.regs[2] == 0x0000,
        "fetch observes the store"
    )
}

/* "A byte read from 0x5FF returns {3'b000, QUIT, RIGHT, LEFT, DOWN, UP}". */
val test_input_port : unit -> unit
function test_input_port() = {
    let keys : bits(5) = 0b10101;
    var s : state = zero_state();
    s.regs[1] = 0x05FF;
    s.regs[2] = 0xBEEF;
    s.mem[1535] = 0xAA;
    assert(
        execute_from(keys, s, LDB(0b000, 0b001, 0b00000)).state.regs[0] == 0x0015,
        "the input byte is {000, keys}"
    );
    let stored = run_one(s, STB(0b010, 0b001, 0b00000));
    assert(stored.mem[1535] == 0xEF, "stores to 0x5FF reach RAM");
    assert(
        execute_from(keys, stored, LDB(0b000, 0b001, 0b00000)).state.regs[0] == 0x0015,
        "reads of 0x5FF still return the input"
    );
    s.mem[1534] = 0x1B; /* LIL R3, <input byte> when fetched from 0x5FE */
    s.regs[1] = 0x05FE;
    assert(
        execute_from(keys, s, LDW(0b000, 0b001, 0b00000)).state.regs[0] == 0x1B15,
        "word reads compose the input byte"
    );
    let fetched = expect_retired(step_from(keys, { s with pc = 0x05FE }));
    assert(fetched.regs[3] == 0x0015 & fetched.pc == 0x0600, "fetch reads the input byte")
}

/* "Pixel (x, y): byte = 0x0600 + y*8 + x/8, bit = 7 - (x mod 8)"; row 0 is the bottom. */
val test_pixels : unit -> unit
function test_pixels() = {
    var s : state = zero_state();
    s.mem[1536] = 0x80;
    s.mem[1536 + 63 * 8 + 7] = 0x01;
    install_state(s);
    assert(pixel(0, 0) & not_bool(pixel(1, 0)) & not_bool(pixel(0, 1)), "bottom-left pixel");
    assert(pixel(63, 63) & not_bool(pixel(62, 63)), "top-right pixel")
}

val test_assembly_syntax : unit -> unit
function test_assembly_syntax() = {
    assert(assembly(NOP()) == "NOP");
    assert(assembly(RET()) == "RET");
    assert(assembly(MOV(0b110, 0b010)) == "MOV R6, R2");
    assert(assembly(LIL(0b001, 0xFF)) == "LIL R1, 255");
    assert(assembly(LIH(0b001, 0x04)) == "LIH R1, 4");
    assert(assembly(LDW(0b001, 0b010, 0b11101)) == "LDW R1, -3(R2)");
    assert(assembly(STB(0b000, 0b110, 0b01111)) == "STB R0, 15(R6)");
    assert(assembly(ADD(0b100, 0b010, 0b011)) == "ADD R4, R2, R3");
    assert(assembly(ADDI(0b101, 0xFF)) == "ADDI R5, -1");
    assert(assembly(SHR(0b011, 0x21)) == "SHR R3, 33");
    assert(assembly(BZ(0b101, 0xFA)) == "BZ R5, -6");
    assert(assembly(JMP(0b11111111010)) == "JMP -6");
    assert(assembly(CALL(0b00000000011)) == "CALL 3");
    assert(assembly(PUSH(0b110)) == "PUSH R6")
}

/* Retirement scratch never leaks between steps. */
val test_scratch_state : unit -> unit
function test_scratch_state() = {
    install_state(seed_state());
    nextPC = 0xFFFF;
    match run_instruction(no_keys, ADD(0b001, 0b001, 0b010)) {
        Retired() => (),
        _ => assert(false, "ADD retires"),
    };
    assert(X(0b001) == 0x8003 & PC == 0x0102, "native register and PC update");
    match run_instruction(no_keys, BZ(0b010, 0xFF)) {
        Retired() => (),
        _ => assert(false, "untaken branch retires"),
    };
    assert(PC == 0x0104, "untaken branch falls through")
}

val main : unit -> unit
function main() = {
    test_all_mnemonics();
    print_endline("PASS: all 27 mnemonics");
    test_aliases();
    print_endline("PASS: operand aliasing and R7 policies");
    test_wrapping();
    print_endline("PASS: 16-bit arithmetic and 11-bit address wrapping");
    test_pc_rules();
    print_endline("PASS: PC masked to 0x7FF, CALL link, branch ranges");
    test_word_alignment();
    print_endline("PASS: word accesses and fetch ignore address bit 0");
    test_shift_count();
    print_endline("PASS: shift count is imm8[4:0]");
    test_arithmetic_ranges();
    print_endline("PASS: 4096 shift inputs per direction; 65536 multiplications");
    test_codec();
    print_endline("PASS: all 65536 words decode, encode and round trip");
    test_illegal();
    print_endline("PASS: opcodes 27-31 stop after the fetch");
    test_halt_and_reset();
    print_endline("PASS: halt latch and reset");
    test_fibonacci();
    print_endline("PASS: hardware-manual Fibonacci program");
    test_live_fetch();
    print_endline("PASS: self-modifying code and physical aliasing");
    test_input_port();
    print_endline("PASS: input port at 0x5FF");
    test_pixels();
    print_endline("PASS: framebuffer pixel mapping");
    test_assembly_syntax();
    print_endline("PASS: assembly syntax");
    test_scratch_state();
    print_endline("PASS: retirement scratch state")
}
