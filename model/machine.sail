/* TARA's machine state and memory buses. Quotations are from the RTL description published with
 * TARA Studio.
 */

default Order dec
$include <prelude.sail>

/*!
= TARA ISA */
$anchor document_title

/*!
TARA (Teaching Architecture for RISC Assembly) is the 16-bit processor of the course CS2300 at IIT
Madras, developed by Ayon Chakraborty. It has eight 16-bit general-purpose registers, 2 KB of
byte-addressed memory shared by code and data, and an input port with five input lines and a 64 by
64 monochrome framebuffer, both mapped into memory.

This is a model of the architecture, not of the microarchitecture: one `step` fetches, decodes and
executes one instruction. It leaves out T-states, the control ROM, memory timing and the status
flags Z, N, C and V, which the RTL calls "observational only": they drive LEDs and never control a
branch.

Quotations are from the RTL description published with TARA Studio <<tara-studio>>. Where that
description is silent, the model makes an assumption and says so beside the definition that makes
it. Where TARA Studio's simulator <<taracpu>> disagrees with the description, the model follows the
description.
 */
$anchor machine

/*!
This document is typeset from a model of TARA in Sail <<sail>>. Each listing is a definition of the
model, and the text beside it is that definition's comment. The listings are normative: where they
and the text disagree, the listings are right.
 */
$anchor document_introduction

/*!
== Machine state */
$anchor section_machine

/*!
A `word` is 16 bits: a register, PC and an instruction are each one word. An `address` selects one
of the 2048 bytes of memory, and a `regidx` one of the eight registers. In the listings, `-` and `^`
on bit vectors are subtraction and exclusive or.
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
The registers R0 to R7. R0 is an ordinary register, not wired to zero. `X` reads and writes them by
number; R6 (`lr`) and R7 (`sp`) have roles in the instruction set.
 */
register GPR : regfile

/*!
The program counter: the byte address of the next instruction. Only its low 11 bits are kept (see
`pc_mask`), so PC wraps around at the end of memory.
 */
register PC : word

/*!
Memory: 2048 bytes, for code, data, the stack, the input port and the framebuffer.

- `0x000` to `0x5FE`: code, data and stack.
- `0x5FF`: the input port; see `read_byte`.
- `0x600` to `0x7FF`: the framebuffer; see `pixel`.

TARA Studio suggests a layout (code from `0x000`, data from `0x400`, the stack below `0x5F0`) that
the architecture does not enforce.
 */
register MEM : memory

/*!
The halt latch. `HLT` sets it and `reset` clears it; while it is set, `step` and `run_instruction`
do nothing.
 */
register HALTED : bool

/*!
The five input lines: UP in bit 0, then DOWN, LEFT, RIGHT, and QUIT in bit 4. The drivers latch
them at the start of each step, so every read of the input port during an instruction, its own
fetch included, sees the same value. The RTL does not say when the lines are sampled; the model
assumes they hold still for an instruction.
 */
register KEYS : bits(5)

/*!
Not architectural state: the address of the next instruction, which `execute` may change before
the drivers write it to PC.
 */
$[notation PC]
register nextPC : word

/*!
Reads register `r`. `X` stands for `rX` and `wX`: `X(r)` reads a register and `X(r) = v` writes
one.
 */
$[notation "R[{0}]"]
function rX(r : regidx) -> word = GPR[unsigned(r)]

/*!
Writes `value` to register `r`. */
$[notation "R[{0}] = {1}"]
function wX(r : regidx, value : word) -> unit = {
    GPR[unsigned(r)] = value
}

overload X = {rX, wX}

/*!
R6, the link register: `CALL` writes the return address to it and `RET` jumps to it. */
let lr : regidx = 0b110

/*!
R7, the stack pointer of `PUSH` and `POP`. */
let sp : regidx = 0b111

/*!
Keeps the low 11 bits of a PC value, as the RTL says: `PC 16-bit, +2 per fetch, masked to 0x7FF`.
Every write of PC but reset's goes through it.
 */
$[notation "{0}"]
function pc_mask(value : word) -> word = 0b00000 @ value[10 .. 0]

/*!
The input port: `A byte read from 0x5FF returns {3'b000, QUIT, RIGHT, LEFT, DOWN, UP}`. */
let input_port : address = 0b10111111111

/*!
Reads a byte. Only the low 11 bits of the address count, so addresses wrap at 2048: `0xFFFF` reads
the byte at `0x7FF`. The input port reads as the input lines, zero-extended.
 */
$[notation "M[{0}](7:0)"]
function read_byte(addr : word) -> byte = {
    let a : address = addr[10 .. 0];
    if a == input_port then {
        0b000 @ KEYS
    } else {
        MEM[unsigned(a)]
    }
}

/*!
Writes a byte at the low 11 bits of the address. A store to the input port writes the memory
behind it, which no read returns.
 */
$[notation "M[{0}](7:0) = {1}"]
function write_byte(addr : word, value : byte) -> unit = {
    MEM[unsigned(addr[10 .. 0])] = value
}

/*!
Reads a big-endian word: the word at `2k` has its high byte at `2k` and its low byte at `2k + 1`.
Bit 0 of the address is ignored (`word index = addr >> 1, lane = addr[0]`), so the last word of
memory is at `0x7FE`. A word read is two byte reads, so a read that covers the input port gets the
input lines as its low byte; the RTL does not say, and the model assumes so. Instruction fetch is a
word read.
 */
$[notation "M[{0}](15:0)"]
function read_word(addr : word) -> word =
    read_byte(addr[15 .. 1] @ 0b0) @ read_byte(addr[15 .. 1] @ 0b1)

/*!
Writes a word, high byte first, ignoring bit 0 of the address as `read_word` does. */
$[notation "M[{0}](15:0) = {1}"]
function write_word(addr : word, value : word) -> unit = {
    write_byte(addr[15 .. 1] @ 0b0, value[15 .. 8]);
    write_byte(addr[15 .. 1] @ 0b1, value[7 .. 0])
}

/*!
Whether the pixel in column x and row y is lit. The framebuffer is the memory from `0x600` to
`0x7FF`: a bit a pixel, eight to a byte with the most significant bit leftmost, and row 0 at the
bottom: `Pixel (x, y): byte = 0x0600 + y*8 + x/8, bit = 7 - (x mod 8)`. There is no other display
state.
 */
val pixel : (range(0, 63), range(0, 63)) -> bool

function pixel(x, y) = {
    let column : bits(6) = get_slice_int(6, x, 0);
    let row : bits(6) = get_slice_int(6, y, 0);
    let pixels = MEM[unsigned(0b11 @ row @ column[5 .. 3])];
    pixels[7 - unsigned(column[2 .. 0])] == bitone
}
