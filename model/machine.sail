/* TARA machine state and memory buses.
 * Quoted rules come from the RTL description on the TARA website; README.md
 * lists the assumptions made where it is silent.
 */

default Order dec
$include <prelude.sail>

/*!
= The TARA Instruction Set Architecture */
$anchor document_title

/*!
TARA (Teaching Architecture for RISC Assembly) is the 16-bit teaching processor of the course
CS2300 at IIT Madras, developed and maintained by Ayon Chakraborty. A TARA machine has eight 16-bit
general-purpose registers, a unified 2 KB byte-addressed memory, a memory-mapped input port with
five input lines and a memory-mapped 64 by 64 monochrome framebuffer.

The model describes the architecture, not the microarchitecture: one call of `step` fetches, decodes
and executes one instruction. T-states, the control ROM, memory timing and the status flags Z, N, C
and V are not modelled. The flags are "observational only" in the RTL: they drive LEDs and debug
outputs, are not architecturally visible and never control a branch.

The model follows the RTL description published with TARA Studio, from which the quotations are
taken. Where that description is silent the model makes an assumption, which is stated with the
definition that implements it; README.md lists them, and the points where the TARA Studio simulator
disagrees with the RTL description.
 */
$anchor machine

/*!
This specification is typeset from the Sail model of TARA, in `model/`. Each listing is a
definition as written there, and the text around it is the definition's documentation comment. The
listings are normative: where text and listing disagree, the listing is right.
 */
$anchor document_introduction

/*!
== Machine state */
$anchor section_machine

/*!
The sizes of the machine are named once: a `word` is the width of a register, of PC and of an
instruction; an `address` is the 11-bit byte address that selects one of the 2048 bytes of memory; a
`regidx` is a register number. The model binds the operators `-` and `^` to bit-vector subtraction
and bitwise exclusive or: this is only notation, the operations themselves come from Sail's library.
 */
$anchor types

overload operator - = {sub_bits}
overload operator ^ = {xor_vec}

type word = bits(16)
type byte = bits(8)
type regidx = bits(3)
type address = bits(11)
type regfile = vector(8, word)
type memory = vector(2048, byte)

/*!
The register file: R0 to R7, each 16 bits wide. R0 is an ordinary writable register, nothing is
hard-wired to zero. Registers are read and written by number through `X`; two of them have a role in
the instruction set, `lr` (R6) and `sp` (R7). The Z/N/C/V status register is "observational only"
and is not modelled.
 */
register GPR : regfile

/*!
The program counter: the byte address of the next instruction. It is 16 bits wide, but only 11
of them are kept, so PC wraps around at the end of the 2 KB memory; see `pc_mask`.
 */
register PC : word

/*!
The memory: 2048 bytes at the addresses `0x000` to `0x7FF`, in which code, data, stack, the input
port and the framebuffer all live.

- `0x000` to `0x5FE`: ordinary memory for program, data and stack, 1535 bytes.
- `0x5FF`: the input port, see `read_byte`.
- `0x600` to `0x7FF`: the framebuffer, 512 bytes, see `pixel`.

The Studio manual suggests a conventional layout (code from `0x000`, data from `0x400`,
a stack below `0x5F0`); the architecture enforces none of it.
 */
register MEM : memory

/*!
The halt latch, set by `HLT` and cleared by `reset`. While it is set, `step` and
`run_instruction` return `Stopped` and change nothing.
 */
register HALTED : bool

/*!
The five input lines: UP in bit 0, then DOWN, LEFT and RIGHT, and QUIT in bit 4. The drivers
latch them once per step, so all reads of the input port during one instruction, including the fetch
of the instruction itself, see the same value: the model assumes that the lines hold still for the
duration of one instruction. How the lines are driven is up to the host.
 */
register KEYS : bits(5)

/*!
Driver scratch, not architectural state: the successor of the current instruction. `retire` sets
it to `PC + 2`, `execute` may replace it, and the drivers then commit it to PC.
 */
register nextPC : word

/*!
Reads a register by number. `X` is the overload of `rX` and `wX`: `X(r)` reads register r, and
`X(r) = v` writes it.
 */
function rX(r : regidx) -> word = GPR[unsigned(r)]

/*!
Writes a register by number; see `rX`. */
function wX(r : regidx, value : word) -> unit = {
    GPR[unsigned(r)] = value
}

overload X = {rX, wX}

/*!
R6 is the link register: `CALL` writes the address of the next instruction to it and `RET` jumps
to it.
 */
let lr : regidx = 0b110

/*!
R7 is the stack pointer, used by `PUSH` and `POP`. */
let sp : regidx = 0b111

/*!
Keeps the low 11 bits of a PC value. The RTL says `PC 16-bit, +2 per fetch, masked to 0x7FF`:
the model writes PC only through this function, and sets it to 0 on reset.
 */
function pc_mask(value : word) -> word = 0b00000 @ value[10 .. 0]

/*!
The address of the input port, the byte `0x5FF`. The RTL says
`A byte read from 0x5FF returns {3'b000, QUIT, RIGHT, LEFT, DOWN, UP}`.
 */
let input_port : address = 0b10111111111

/*!
The byte bus. The low 11 bits of the address select a byte of the 2 KB memory, so addresses wrap
modulo 2048: an effective address computed as `0 - 1` selects byte `0x7FF`, and `0xF802` selects
byte `0x002`. A read of the input port returns the five input lines held in `KEYS`, zero-extended;
any other address reads the memory.
 */
function read_byte(addr : word) -> byte = {
    let a : address = addr[10 .. 0];
    if a == input_port then {
        0b000 @ KEYS
    } else {
        MEM[unsigned(a)]
    }
}

/*!
Stores a byte, at the low 11 bits of the address. A store to the input port is not special: it
writes the memory byte behind it, which no read returns. Memory has a single write port, and a byte
store is a read-modify-write of a word.
 */
function write_byte(addr : word, value : byte) -> unit = {
    MEM[unsigned(addr[10 .. 0])] = value
}

/*!
The word bus. The RTL gives the rule `word index = addr >> 1, lane = addr[0]` and stores words
big-endian: the word at address `2k` has its high byte in byte `2k` and its low byte in byte
`2k + 1`. A word access ignores address bit 0, so an access to the odd address `2k + 1` is an access
to the word at `2k`, and the last word of memory is the one at `0x7FE`. A word access is two byte
accesses, so a read that covers the input port gets the input lines as its low byte: the model
assumes this where the RTL is silent. Instruction fetch is a word read.
 */
function read_word(addr : word) -> word =
    read_byte(addr[15 .. 1] @ 0b0) @ read_byte(addr[15 .. 1] @ 0b1)

/*!
Stores a word, high byte first. As for `read_word`, bit 0 of the address is ignored. */
function write_word(addr : word, value : word) -> unit = {
    write_byte(addr[15 .. 1] @ 0b0, value[15 .. 8]);
    write_byte(addr[15 .. 1] @ 0b1, value[7 .. 0])
}

/*!
The 64 by 64 framebuffer occupies `0x600` to `0x7FF`: 512 bytes, one bit per pixel, eight pixels per
byte with the most significant bit on the left. Row 0 is the bottom of the display. The RTL gives
the mapping `Pixel (x, y): byte = 0x0600 + y*8 + x/8, bit = 7 - (x mod 8)`. The model has no
separate display state: `pixel` reads the memory and tells whether the pixel in column x and row y
is lit.
 */
val pixel : (range(0, 63), range(0, 63)) -> bool

function pixel(x, y) = {
    let column : bits(6) = get_slice_int(6, x, 0);
    let row : bits(6) = get_slice_int(6, y, 0);
    let pixels = MEM[unsigned(0b11 @ row @ column[5 .. 3])];
    pixels[7 - unsigned(column[2 .. 0])] == bitone
}
