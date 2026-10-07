/*!
@anchor section_memory
=== Memory

@anchor memory
A load or store addresses `base + off`, where `off` counts bytes, -16 to 15, and the sum wraps at
16 bits. Memory uses only the low 11 address bits; a word access ignores bit 0. The byte at
`0x5FF` reads as the input port.
 */
union clause instruction = LDW : (regidx, regidx, bits(5))
mapping clause encdec = LDW(rd, base, off) <-> 0b00101 : opcode @ rd @ base @ off

/*!
@brief Load word

Loads the word at `base + off` into `rd`.

@param rd Destination register.
@param base Base address register.
@param off Signed address displacement in bytes.
@note The effective address wraps to 16 bits. Memory keeps its low 11 bits and ignores bit 0 for
word access.
@assumption A word covering the input port reads the input lines as its low byte.
@see LDB, STW
 */
function clause execute(LDW(rd, base, off)) = {
    X(rd) = read_word(X(base) + signed(off))
}

union clause instruction = STW : (regidx, regidx, bits(5))
mapping clause encdec = STW(rs, base, off) <-> 0b00110 : opcode @ rs @ base @ off

/*!
@brief Store word

Stores `rs` as the word at `base + off`.

@param rs Source register.
@param base Base address register.
@param off Signed address displacement in bytes.
@note The effective address wraps to 16 bits. Word stores ignore address bit 0 and write the high
byte first.
@see STB, LDW
 */
function clause execute(STW(rs, base, off)) = {
    write_word(X(base) + signed(off), X(rs))
}

union clause instruction = LDB : (regidx, regidx, bits(5))
mapping clause encdec = LDB(rd, base, off) <-> 0b00111 : opcode @ rd @ base @ off

/*!
@brief Load byte

Loads the byte at `base + off` into `rd`, zero-extended.

@param rd Destination register.
@param base Base address register.
@param off Signed address displacement in bytes.
@note The byte is zero-extended to 16 bits. Only the low 11 address bits select memory.
@see LDW, STB
 */
function clause execute(LDB(rd, base, off)) = {
    X(rd) = 0x00 @ read_byte(X(base) + signed(off))
}

union clause instruction = STB : (regidx, regidx, bits(5))
mapping clause encdec = STB(rs, base, off) <-> 0b01000 : opcode @ rs @ base @ off

/*!
@brief Store byte

Stores the low byte of `rs` at `base + off`.

@param rs Source register.
@param base Base address register.
@param off Signed address displacement in bytes.
@note Only the low byte of the source register is stored.
@assumption A store to the input port writes the RAM byte behind it; reads return the input lines.
@see STW, LDB
 */
function clause execute(STB(rs, base, off)) = {
    write_byte(X(base) + signed(off), X(rs)[7 .. 0])
}
