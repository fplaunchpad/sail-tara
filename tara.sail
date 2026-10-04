/* TARA instruction-retirement semantics, v0.5.
 *
 * Read this file first. Each instruction gives its operands, encoding payload,
 * and execution. rd is a destination; rs/rs1/rs2 are sources. X reads/writes a
 * writable 16-bit register. signed interprets two's complement; @ joins bits.
 * Arithmetic wraps at the destination width. Memory offsets count bytes.
 *
 * Entry points: run_instruction(env, insn) for a decoded instruction; step(env)
 * for live-memory fetch/decode/execute. execute is their internal clause worker:
 * PC remains the old PC, and nextPC holds the proposed successor until commit.
 * PROFILE.md records the unresolved hardware choices; README.md records status.
 */
$ifndef _ISA_SPEC
$define _ISA_SPEC
$include "machine.sail"

scattered union instruction

val encdec_fields : instruction <-> (mnemonic, bits(11))
scattered mapping encdec_fields

val execute : instruction -> unit
scattered function execute

/* No operation and halt. HLT still retires and advances PC. */

union clause instruction = NOP : unit
mapping clause encdec_fields =
  NOP() <-> (M_NOP, 0b00000000000)

function clause execute NOP() = {
  ()
}

union clause instruction = HLT : unit
mapping clause encdec_fields =
  HLT() <-> (M_HLT, 0b00000000000)

function clause execute HLT() = {
  HALTED = true
}

/* Register moves and byte immediates.
 * LIL clears the upper byte; LIH changes only the upper byte. */

union clause instruction = MOV : (regidx, regidx)
mapping clause encdec_fields =
  MOV(rd, rs) <-> (M_MOV, rd @ rs @ 0b00000)

function clause execute MOV(rd, rs) = {
  X(rd) = X(rs)
}

union clause instruction = LIL : (regidx, bits(8))
mapping clause encdec_fields =
  LIL(rd, imm) <-> (M_LIL, rd @ imm)

function clause execute LIL(rd, imm) = {
  X(rd) = 0x00 @ imm
}

union clause instruction = LIH : (regidx, bits(8))
mapping clause encdec_fields =
  LIH(rd, imm) <-> (M_LIH, rd @ imm)

function clause execute LIH(rd, imm) = {
  X(rd) = imm @ X(rd)[7..0]
}

/* Data memory: (data register, base register, signed BYTE offset). */

union clause instruction = LDW : (regidx, regidx, bits(5))
mapping clause encdec_fields =
  LDW(rd, base, off) <-> (M_LDW, rd @ base @ off)

function clause execute LDW(rd, base, off) = {
  let addr : word = X(base) + signed(off);
  X(rd) = load_word(addr)
}

union clause instruction = STW : (regidx, regidx, bits(5))
mapping clause encdec_fields =
  STW(rs, base, off) <-> (M_STW, rs @ base @ off)

function clause execute STW(rs, base, off) = {
  let addr : word = X(base) + signed(off);
  store_word(addr, X(rs))
}

union clause instruction = LDB : (regidx, regidx, bits(5))
mapping clause encdec_fields =
  LDB(rd, base, off) <-> (M_LDB, rd @ base @ off)

function clause execute LDB(rd, base, off) = {
  let addr : word = X(base) + signed(off);
  X(rd) = 0x00 @ load_byte(addr)
}

union clause instruction = STB : (regidx, regidx, bits(5))
mapping clause encdec_fields =
  STB(rs, base, off) <-> (M_STB, rs @ base @ off)

function clause execute STB(rs, base, off) = {
  let addr : word = X(base) + signed(off);
  store_byte(addr, X(rs)[7..0])
}

/* Arithmetic: 16-bit results; ADDI has a signed immediate. */

union clause instruction = ADD : (regidx, regidx, regidx)
mapping clause encdec_fields =
  ADD(rd, rs1, rs2) <-> (M_ADD, rd @ rs1 @ rs2 @ 0b00)

function clause execute ADD(rd, rs1, rs2) = {
  X(rd) = X(rs1) + X(rs2)
}

union clause instruction = SUB : (regidx, regidx, regidx)
mapping clause encdec_fields =
  SUB(rd, rs1, rs2) <-> (M_SUB, rd @ rs1 @ rs2 @ 0b00)

function clause execute SUB(rd, rs1, rs2) = {
  X(rd) = X(rs1) - X(rs2)
}

union clause instruction = ADDI : (regidx, bits(8))
mapping clause encdec_fields =
  ADDI(rd, imm) <-> (M_ADDI, rd @ imm)

function clause execute ADDI(rd, imm) = {
  X(rd) = X(rd) + signed(imm)
}

union clause instruction = MUL : (regidx, regidx, regidx)
mapping clause encdec_fields =
  MUL(rd, rs1, rs2) <-> (M_MUL, rd @ rs1 @ rs2 @ 0b00)

function clause execute MUL(rd, rs1, rs2) = {
  let product = unsigned(X(rs1)) * unsigned(X(rs2));
  X(rd) = get_slice_int(16, product, 0)  /* Keep the low 16 product bits. */
}

/* Bitwise operations and logical shifts.
 * Use the full unsigned 8-bit count. Counts >=16 produce zero; do not mask. */

union clause instruction = AND : (regidx, regidx, regidx)
mapping clause encdec_fields =
  AND(rd, rs1, rs2) <-> (M_AND, rd @ rs1 @ rs2 @ 0b00)

function clause execute AND(rd, rs1, rs2) = {
  X(rd) = X(rs1) & X(rs2)
}

union clause instruction = OR : (regidx, regidx, regidx)
mapping clause encdec_fields =
  OR(rd, rs1, rs2) <-> (M_OR, rd @ rs1 @ rs2 @ 0b00)

function clause execute OR(rd, rs1, rs2) = {
  X(rd) = X(rs1) | X(rs2)
}

union clause instruction = XOR : (regidx, regidx, regidx)
mapping clause encdec_fields =
  XOR(rd, rs1, rs2) <-> (M_XOR, rd @ rs1 @ rs2 @ 0b00)

function clause execute XOR(rd, rs1, rs2) = {
  X(rd) = X(rs1) ^ X(rs2)
}

union clause instruction = NOT : (regidx, regidx)
mapping clause encdec_fields =
  NOT(rd, rs) <-> (M_NOT, rd @ rs @ 0b00000)

function clause execute NOT(rd, rs) = {
  X(rd) = not_vec(X(rs))
}

union clause instruction = SHL : (regidx, bits(8))
mapping clause encdec_fields =
  SHL(rd, shamt) <-> (M_SHL, rd @ shamt)

function clause execute SHL(rd, shamt) = {
  let amount = unsigned(shamt);
  X(rd) = if amount >= 16 then 0x0000 else sail_shiftleft(X(rd), amount)
}

union clause instruction = SHR : (regidx, bits(8))
mapping clause encdec_fields =
  SHR(rd, shamt) <-> (M_SHR, rd @ shamt)

function clause execute SHR(rd, shamt) = {
  let amount = unsigned(shamt);
  X(rd) = if amount >= 16 then 0x0000 else sail_shiftright(X(rd), amount)
}

/* Signed comparison. */

union clause instruction = SLT : (regidx, regidx, regidx)
mapping clause encdec_fields =
  SLT(rd, rs1, rs2) <-> (M_SLT, rd @ rs1 @ rs2 @ 0b00)

function clause execute SLT(rd, rs1, rs2) = {
  X(rd) = if signed(X(rs1)) < signed(X(rs2)) then 0x0001 else 0x0000
}

/* Control flow. PC is the current instruction address until retirement.
 * A relative target is PC + 2 + 2*signed(off); offsets count instructions. */

union clause instruction = BZ : (regidx, bits(8))
mapping clause encdec_fields =
  BZ(rs, off) <-> (M_BZ, rs @ off)

function clause execute BZ(rs, off) = {
  if X(rs) == 0x0000 then nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = BN : (regidx, bits(8))
mapping clause encdec_fields =
  BN(rs, off) <-> (M_BN, rs @ off)

function clause execute BN(rs, off) = {
  if signed(X(rs)) < 0 then nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = JMP : bits(11)
mapping clause encdec_fields =
  JMP(off) <-> (M_JMP, off)

function clause execute JMP(off) = {
  nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = CALL : bits(11)
mapping clause encdec_fields =
  CALL(off) <-> (M_CALL, off)

function clause execute CALL(off) = {
  X(lr) = PC + 0x0002;
  nextPC = PC + 0x0002 + 2 * signed(off)
}

union clause instruction = RET : unit
mapping clause encdec_fields =
  RET() <-> (M_RET, 0b00000000000)

function clause execute RET() = {
  nextPC = X(lr)
}

/* Stack operations: explicit R7 alias policy. */

union clause instruction = PUSH : regidx
mapping clause encdec_fields =
  PUSH(rs) <-> (M_PUSH, rs @ 0x00)

function clause execute PUSH(rs) = {
  let addr : word = X(sp) - 0x0002;
  /* PUSH R7 stores the decremented SP, not the old SP. */
  let value : word = if rs == sp then addr else X(rs);
  store_word(addr, value);  /* Check/store before changing SP: no rollback. */
  X(sp) = addr
}

union clause instruction = POP : regidx
mapping clause encdec_fields =
  POP(rd) <-> (M_POP, rd @ 0x00)

function clause execute POP(rd) = {
  let value = load_word(X(sp));
  X(rd) = value;
  X(sp) = X(sp) + 0x0002  /* POP R7 increments the value just loaded. */
}

end instruction
end encdec_fields
end execute

$include "encoding.sail"
$include "step.sail"
$endif
