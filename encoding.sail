/* Included after the instruction clauses. Layouts live beside instructions;
 * this file supplies only numeric opcode selection and boundary reporting.
 * encode/decode return their value or throw SpecificationBoundary(issue).
 */
type opcode_table = vector(32, option(mnemonic))

function opcodes_valid(table : opcode_table) -> bool = {
  foreach (i from 0 to 31) {
    foreach (j from 0 to 31) {
      if i < j then match (table[i], table[j]) {
        (Some(a), Some(b)) => if a == b then return false,
        _ => ()
      }
    }
  };
  true
}

function check_opcodes(table : opcode_table) -> unit = {
  if not_bool(opcodes_valid(table)) then
    throw(SpecificationBoundary(NoninjectiveOpcodeMap()))
}

function find_opcode(table : opcode_table, mnemonic : mnemonic) -> option(opcode) = {
  foreach (j from 0 to 31) {
    match table[j] {
      Some(m) => if m == mnemonic then return Some(get_slice_int(5, j, 0)),
      None() => ()
    }
  };
  None()
}

function encode_with(table : opcode_table, insn : instruction) -> word = {
  check_opcodes(table);
  let (mnemonic, payload) = encdec_fields(insn);
  match find_opcode(table, mnemonic) {
    Some(op) => op @ payload,
    None() => throw(SpecificationBoundary(MissingEncoding(mnemonic)))
  }
}

/* The partial mapping is matched, not called unchecked in reverse. Nonzero
 * padding is therefore a reported model boundary, never a mapping failure. */
function decode_with(table : opcode_table, raw : word) -> instruction = {
  check_opcodes(table);
  match table[unsigned(raw[15..11])] {
    Some(mnemonic) => match (mnemonic, raw[10..0]) {
      encdec_fields(insn) => insn,
      _ => throw(SpecificationBoundary(NoncanonicalPadding(raw)))
    },
    None() => throw(SpecificationBoundary(UnverifiedOpcode(raw[15..11])))
  }
}

/* Only these seven assignments are evidenced by the hardware manual's
 * Fibonacci words. No remaining opcode is guessed from an enum ordinal. */
function evidenced_opcodes() -> opcode_table = {
  var table : opcode_table = vector_init(32, None());
  table[1] = Some(M_HLT);
  table[2] = Some(M_MOV);
  table[3] = Some(M_LIL);
  table[9] = Some(M_ADD);
  table[11] = Some(M_ADDI);
  table[20] = Some(M_BZ);
  table[22] = Some(M_JMP);
  table
}

function encode(insn : instruction) -> word = encode_with(evidenced_opcodes(), insn)

function decode(raw : word) -> instruction = decode_with(evidenced_opcodes(), raw)
