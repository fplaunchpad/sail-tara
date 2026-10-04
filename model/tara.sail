/* TARA instruction semantics.
 *
 * Each instruction gives its operands, its 16-bit encoding (5-bit opcode, then
 * operand fields) and its effect, side by side. Decoding ignores the unused
 * padding bits; encoding writes them as zero. rd is a destination; rs, rs1 and
 * rs2 are sources. X(r) reads or writes a register. Arithmetic wraps at 16
 * bits. Memory offsets count bytes; branch offsets count instructions.
 *
 * execute sees PC as the address of the current instruction and proposes the
 * successor in nextPC; the drivers in step.sail commit it.
 */

$ifndef _TARA_SAIL
$define _TARA_SAIL
$include "machine.sail"

scattered union instruction

val encode : instruction -> word
scattered function encode

val decode : word -> option(instruction)
scattered function decode

val execute : instruction -> unit
scattered function execute

/* No operation and halt. HLT retires, advancing PC, then halts the CPU. */

union clause instruction = NOP : unit
function clause encode(NOP()) = 0b00000 @ 0b00000000000
function clause decode(0b00000 @ _ : bits(11)) = Some(NOP())
function clause execute(NOP()) = ()

union clause instruction = HLT : unit
function clause encode(HLT()) = 0b00001 @ 0b00000000000
function clause decode(0b00001 @ _ : bits(11)) = Some(HLT())
function clause execute(HLT()) = {
    HALTED = true
}

/* Register moves and byte immediates.
 * LIL clears the upper byte; LIH changes only the upper byte. */

union clause instruction = MOV : (regidx, regidx)
function clause encode(MOV(rd, rs)) = 0b00010 @ rd @ rs @ 0b00000
function clause decode(0b00010 @ rd : regidx @ rs : regidx @ _ : bits(5)) = Some(MOV(rd, rs))
function clause execute(MOV(rd, rs)) = {
    X(rd) = X(rs)
}

union clause instruction = LIL : (regidx, bits(8))
function clause encode(LIL(rd, imm)) = 0b00011 @ rd @ imm
function clause decode(0b00011 @ rd : regidx @ imm : bits(8)) = Some(LIL(rd, imm))
function clause execute(LIL(rd, imm)) = {
    X(rd) = 0x00 @ imm
}

union clause instruction = LIH : (regidx, bits(8))
function clause encode(LIH(rd, imm)) = 0b00100 @ rd @ imm
function clause decode(0b00100 @ rd : regidx @ imm : bits(8)) = Some(LIH(rd, imm))
function clause execute(LIH(rd, imm)) = {
    X(rd) = imm @ X(rd)[7 .. 0]
}

/* Memory: (data register, base register, signed byte offset). */

union clause instruction = LDW : (regidx, regidx, bits(5))
function clause encode(LDW(rd, base, off)) = 0b00101 @ rd @ base @ off
function clause decode(0b00101 @ rd : regidx @ base : regidx @ off : bits(5)) =
    Some(LDW(rd, base, off))
function clause execute(LDW(rd, base, off)) = {
    X(rd) = read_word(X(base) + signed(off))
}

union clause instruction = STW : (regidx, regidx, bits(5))
function clause encode(STW(rs, base, off)) = 0b00110 @ rs @ base @ off
function clause decode(0b00110 @ rs : regidx @ base : regidx @ off : bits(5)) =
    Some(STW(rs, base, off))
function clause execute(STW(rs, base, off)) = {
    write_word(X(base) + signed(off), X(rs))
}

union clause instruction = LDB : (regidx, regidx, bits(5))
function clause encode(LDB(rd, base, off)) = 0b00111 @ rd @ base @ off
function clause decode(0b00111 @ rd : regidx @ base : regidx @ off : bits(5)) =
    Some(LDB(rd, base, off))
function clause execute(LDB(rd, base, off)) = {
    X(rd) = 0x00 @ read_byte(X(base) + signed(off))
}

union clause instruction = STB : (regidx, regidx, bits(5))
function clause encode(STB(rs, base, off)) = 0b01000 @ rs @ base @ off
function clause decode(0b01000 @ rs : regidx @ base : regidx @ off : bits(5)) =
    Some(STB(rs, base, off))
function clause execute(STB(rs, base, off)) = {
    write_byte(X(base) + signed(off), X(rs)[7 .. 0])
}

/* Arithmetic. ADDI has a signed immediate; MUL keeps the low 16 bits. */

union clause instruction = ADD : (regidx, regidx, regidx)
function clause encode(ADD(rd, rs1, rs2)) = 0b01001 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01001 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(ADD(rd, rs1, rs2))
function clause execute(ADD(rd, rs1, rs2)) = {
    X(rd) = X(rs1) + X(rs2)
}

union clause instruction = SUB : (regidx, regidx, regidx)
function clause encode(SUB(rd, rs1, rs2)) = 0b01010 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01010 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(SUB(rd, rs1, rs2))
function clause execute(SUB(rd, rs1, rs2)) = {
    X(rd) = X(rs1) - X(rs2)
}

union clause instruction = ADDI : (regidx, bits(8))
function clause encode(ADDI(rd, imm)) = 0b01011 @ rd @ imm
function clause decode(0b01011 @ rd : regidx @ imm : bits(8)) = Some(ADDI(rd, imm))
function clause execute(ADDI(rd, imm)) = {
    X(rd) = X(rd) + signed(imm)
}

union clause instruction = MUL : (regidx, regidx, regidx)
function clause encode(MUL(rd, rs1, rs2)) = 0b01100 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01100 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(MUL(rd, rs1, rs2))
function clause execute(MUL(rd, rs1, rs2)) = {
    X(rd) = get_slice_int(16, unsigned(X(rs1)) * unsigned(X(rs2)), 0)
}

/* Bitwise operations and logical shifts. "shamt = imm8[4:0]": counts of 16
 * to 31 shift every bit out. */

union clause instruction = AND : (regidx, regidx, regidx)
function clause encode(AND(rd, rs1, rs2)) = 0b01101 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01101 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(AND(rd, rs1, rs2))
function clause execute(AND(rd, rs1, rs2)) = {
    X(rd) = X(rs1) & X(rs2)
}

union clause instruction = OR : (regidx, regidx, regidx)
function clause encode(OR(rd, rs1, rs2)) = 0b01110 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01110 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(OR(rd, rs1, rs2))
function clause execute(OR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) | X(rs2)
}

union clause instruction = XOR : (regidx, regidx, regidx)
function clause encode(XOR(rd, rs1, rs2)) = 0b01111 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b01111 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(XOR(rd, rs1, rs2))
function clause execute(XOR(rd, rs1, rs2)) = {
    X(rd) = X(rs1) ^ X(rs2)
}

union clause instruction = NOT : (regidx, regidx)
function clause encode(NOT(rd, rs)) = 0b10000 @ rd @ rs @ 0b00000
function clause decode(0b10000 @ rd : regidx @ rs : regidx @ _ : bits(5)) = Some(NOT(rd, rs))
function clause execute(NOT(rd, rs)) = {
    X(rd) = not_vec(X(rs))
}

union clause instruction = SHL : (regidx, bits(8))
function clause encode(SHL(rd, shamt)) = 0b10001 @ rd @ shamt
function clause decode(0b10001 @ rd : regidx @ shamt : bits(8)) = Some(SHL(rd, shamt))
function clause execute(SHL(rd, shamt)) = {
    X(rd) = sail_shiftleft(X(rd), unsigned(shamt[4 .. 0]))
}

union clause instruction = SHR : (regidx, bits(8))
function clause encode(SHR(rd, shamt)) = 0b10010 @ rd @ shamt
function clause decode(0b10010 @ rd : regidx @ shamt : bits(8)) = Some(SHR(rd, shamt))
function clause execute(SHR(rd, shamt)) = {
    X(rd) = sail_shiftright(X(rd), unsigned(shamt[4 .. 0]))
}

/* Signed comparison. */

union clause instruction = SLT : (regidx, regidx, regidx)
function clause encode(SLT(rd, rs1, rs2)) = 0b10011 @ rd @ rs1 @ rs2 @ 0b00
function clause decode(0b10011 @ rd : regidx @ rs1 : regidx @ rs2 : regidx @ _ : bits(2)) =
    Some(SLT(rd, rs1, rs2))
function clause execute(SLT(rd, rs1, rs2)) = {
    X(rd) = if signed(X(rs1)) < signed(X(rs2)) then { 0x0001 } else { 0x0000 }
}

/* Control flow. A relative target is PC + 2 + 2 * signed(off). BZ and BN test
 * the register itself, never the status flags. CALL links the masked PC + 2. */

union clause instruction = BZ : (regidx, bits(8))
function clause encode(BZ(rs, off)) = 0b10100 @ rs @ off
function clause decode(0b10100 @ rs : regidx @ off : bits(8)) = Some(BZ(rs, off))
function clause execute(BZ(rs, off)) = {
    if X(rs) == 0x0000 then {
        nextPC = PC + 0x0002 + 2 * signed(off)
    }
}

union clause instruction = BN : (regidx, bits(8))
function clause encode(BN(rs, off)) = 0b10101 @ rs @ off
function clause decode(0b10101 @ rs : regidx @ off : bits(8)) = Some(BN(rs, off))
function clause execute(BN(rs, off)) = {
    if X(rs)[15] == bitone then {
        nextPC = PC + 0x0002 + 2 * signed(off)
    }
}

union clause instruction = JMP : bits(11)
function clause encode(JMP(off)) = 0b10110 @ off
function clause decode(0b10110 @ off : bits(11)) = Some(JMP(off))
function clause execute(JMP(off)) = {
    nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = CALL : bits(11)
function clause encode(CALL(off)) = 0b10111 @ off
function clause decode(0b10111 @ off : bits(11)) = Some(CALL(off))
function clause execute(CALL(off)) = {
    X(lr) = pc_mask(PC + 0x0002);
    nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = RET : unit
function clause encode(RET()) = 0b11000 @ 0b00000000000
function clause decode(0b11000 @ _ : bits(11)) = Some(RET())
function clause execute(RET()) = {
    nextPC = X(lr)
}

/* Stack, following the ISA table's order: PUSH R7 stores the decremented SP;
 * POP R7 increments the value just loaded. */

union clause instruction = PUSH : regidx
function clause encode(PUSH(rs)) = 0b11001 @ rs @ 0x00
function clause decode(0b11001 @ rs : regidx @ _ : bits(8)) = Some(PUSH(rs))
function clause execute(PUSH(rs)) = {
    X(sp) = X(sp) - 0x0002;
    write_word(X(sp), X(rs))
}

union clause instruction = POP : regidx
function clause encode(POP(rd)) = 0b11010 @ rd @ 0x00
function clause decode(0b11010 @ rd : regidx @ _ : bits(8)) = Some(POP(rd))
function clause execute(POP(rd)) = {
    X(rd) = read_word(X(sp));
    X(sp) = X(sp) + 0x0002
}

/* Opcodes 27 to 31 are unassigned. */
function clause decode(_) = None()

end instruction
end encode
end decode
end execute

$include "step.sail"
$endif
