/* Machine support: state, specification boundaries, and the byte bus.
 * Instruction-specific arithmetic stays beside the instruction in tara.sail.
 * The byte bus is total after word alignment is checked. This is essential to
 * the unchanged-architecture boundary contract; exceptions do not roll back.
 */
default Order dec
$include <prelude.sail>

/* Only notation: the operations themselves come from Sail's library. */
overload operator - = {sub_bits}
overload operator ^ = {xor_vec}

type word = bits(16)
type byte = bits(8)
type regidx = bits(3)
type opcode = bits(5)
type physical_address = bits(11)
type regfile = vector(8, word)
type memory = vector(2048, byte)

/* These four registers are the architectural state. R0 is writable. */
register GPR : regfile
register PC : word
register MEM : memory
register HALTED : bool

function rX(r : regidx) -> word = GPR[unsigned(r)]

function wX(r : regidx, value : word) -> unit = { GPR[unsigned(r)] = value }

overload X = {rX, wX}

let lr : regidx = 0b110
let sp : regidx = 0b111

/* Driver scratch, NOT a ninth general register or extra architectural PC.
 * retire sets this to PC+2; branches replace it; only retirement commits PC. */
register nextPC : word

/* Tags distinguish instruction identity from numeric opcodes. The enum order
 * is not an encoding assignment. Only encoding.sail interprets opcode numbers. */
enum mnemonic = {
  M_NOP, M_HLT, M_MOV, M_LIL, M_LIH, M_LDW, M_STW, M_LDB, M_STB,
  M_ADD, M_SUB, M_ADDI, M_MUL, M_AND, M_OR, M_XOR, M_NOT, M_SHL,
  M_SHR, M_SLT, M_BZ, M_BN, M_JMP, M_CALL, M_RET, M_PUSH, M_POP
}

union issue = {
  OddInstructionFetch : word,
  OddWordAccess : word,
  UnverifiedOpcode : opcode,
  NoncanonicalPadding : word,
  NoninjectiveOpcodeMap : unit,
  MissingEncoding : mnemonic
}

/* A Sail control-flow exception, NOT a TARA trap. Catching it does not roll
 * back writes. Every possible boundary must precede architectural writes. */
union exception = { SpecificationBoundary : issue }

union outcome = {
  Retired : unit,
  Stopped : unit,
  NeedsSpecification : issue
}

function check_word_alignment(addr : word) -> unit = {
  if addr[0] == bitone then throw(SpecificationBoundary(OddWordAccess(addr)))
}

/* Platform inputs and observations are model bookkeeping, not CPU registers.
 * Platform is fixed for one instruction attempt. Events retain the previous
 * public convention: fetch slots 0,1 and data slots 2,3, in INDEX order.
 * Instruction clauses never handle these slots themselves. */
union environment = {
  PlainRAM : unit,
  KeyboardFramebuffer : bits(5)
}

union event = {
  InputRead : (physical_address, byte),
  InputWriteIgnored : (physical_address, byte),
  FramebufferWrite : (physical_address, byte)
}

type events = vector(4, option(event))
register Platform : environment
register Events : events

/* Name access roles at call sites; flatten them only for the public trace.
 * Fetch bytes occupy slots 0,1; data bytes occupy slots 2,3. */
enum access_kind = { Fetch, Data }
type byte_index = range(0, 1)

function event_slot(kind : access_kind, index : byte_index) -> range(0, 3) =
  match kind { Fetch => index, Data => 2 + index }

let keyboard_address = 1535
let framebuffer_start = 1536

/* Internal byte bus. Low 11 address bits select physical memory.
 * Each byte access fills exactly one observation slot, including None. */
function bus_read_byte(addr : word, kind : access_kind, index : byte_index) -> byte = {
  let p : physical_address = addr[10..0];
  let slot = event_slot(kind, index);
  Events[slot] = None();
  match Platform {
    KeyboardFramebuffer(keys) =>
      if unsigned(p) == keyboard_address then {
        let value : byte = 0b000 @ keys;
        Events[slot] = Some(InputRead(p, value));
        value
      } else MEM[unsigned(p)],
    PlainRAM() => MEM[unsigned(p)]
  }
}

function bus_write_byte(addr : word, value : byte,
                        kind : access_kind, index : byte_index) -> unit = {
  let p : physical_address = addr[10..0];
  let slot = event_slot(kind, index);
  Events[slot] = None();
  match Platform {
    KeyboardFramebuffer(_) =>
      if unsigned(p) == keyboard_address then {
        Events[slot] = Some(InputWriteIgnored(p, value))
      } else {
        MEM[unsigned(p)] = value;
        if unsigned(p) >= framebuffer_start then
          Events[slot] = Some(FramebufferWrite(p, value))
      },
    PlainRAM() => { MEM[unsigned(p)] = value }
  }
}

/* Big-endian word bus. Callers check alignment before making either access.
 * Separate lets make the high-byte / low-byte observation order explicit. */
function bus_read_word(addr : word, kind : access_kind) -> word = {
  let hi = bus_read_byte(addr, kind, 0);
  let lo = bus_read_byte(addr + 0x0001, kind, 1);
  hi @ lo
}

function bus_write_word(addr : word, value : word, kind : access_kind) -> unit = {
  bus_write_byte(addr, value[15..8], kind, 0);
  bus_write_byte(addr + 0x0001, value[7..0], kind, 1)
}

/* Instruction-facing data access. Odd words fail before any data observation
 * or architectural write; the underlying byte bus has no later failures. */
function load_byte(addr : word) -> byte = bus_read_byte(addr, Data, 0)

function store_byte(addr : word, value : byte) -> unit = bus_write_byte(addr, value, Data, 0)

function load_word(addr : word) -> word = {
  check_word_alignment(addr);
  bus_read_word(addr, Data)
}

function store_word(addr : word, value : word) -> unit = {
  check_word_alignment(addr);
  bus_write_word(addr, value, Data)
}
