/*!
=== Memory */
$anchor section_memory

/*! A memory instruction names a data register, a base register `base` and a signed offset `off` in
bytes, -16 to 15. The effective address is `base + off`, which wraps at 16 bits; the rules of the
byte and word buses (see `read_byte` and `read_word`) then apply to it: only its low 11 bits count,
and a word access ignores bit 0. Words are big-endian, and a byte read of address 0x5FF returns the
input port.
 */
$anchor memory

union clause instruction = LDW : (regidx, regidx, bits(5))
function clause encode(LDW(rd, base, off)) = 0b00101 @ rd @ base @ off
function clause decode(0b00101 @ rd : regidx @ base : regidx @ off : bits(5)) =
    Some(LDW(rd, base, off))
/*! Loads the word at the effective address `base + off` into `rd`. */
function clause execute(LDW(rd, base, off)) = {
    X(rd) = read_word(X(base) + signed(off))
}

union clause instruction = STW : (regidx, regidx, bits(5))
function clause encode(STW(rs, base, off)) = 0b00110 @ rs @ base @ off
function clause decode(0b00110 @ rs : regidx @ base : regidx @ off : bits(5)) =
    Some(STW(rs, base, off))
/*! Stores `rs` as the word at the effective address `base + off`, high byte first. */
function clause execute(STW(rs, base, off)) = {
    write_word(X(base) + signed(off), X(rs))
}

union clause instruction = LDB : (regidx, regidx, bits(5))
function clause encode(LDB(rd, base, off)) = 0b00111 @ rd @ base @ off
function clause decode(0b00111 @ rd : regidx @ base : regidx @ off : bits(5)) =
    Some(LDB(rd, base, off))
/*! Loads the byte at the effective address `base + off` into the low byte of `rd` and clears the
upper byte.
 */
function clause execute(LDB(rd, base, off)) = {
    X(rd) = 0x00 @ read_byte(X(base) + signed(off))
}

union clause instruction = STB : (regidx, regidx, bits(5))
function clause encode(STB(rs, base, off)) = 0b01000 @ rs @ base @ off
function clause decode(0b01000 @ rs : regidx @ base : regidx @ off : bits(5)) =
    Some(STB(rs, base, off))
/*! Stores the low byte of `rs` at the effective address `base + off`. */
function clause execute(STB(rs, base, off)) = {
    write_byte(X(base) + signed(off), X(rs)[7 .. 0])
}
