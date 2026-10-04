/* TARA machine state and memory buses.
 * Quoted rules come from the RTL description on the TARA website; README.md
 * lists the assumptions made where it is silent.
 */

default Order dec
$include <prelude.sail>

/* Only notation: the operations themselves come from Sail's library. */
overload operator - = {sub_bits}
overload operator ^ = {xor_vec}

type word = bits(16)
type byte = bits(8)
type regidx = bits(3)
type address = bits(11)
type regfile = vector(8, word)
type memory = vector(2048, byte)

/* Architectural state. R0 is an ordinary writable register. The Z/N/C/V
 * status register is "observational only" and is not modelled. */
register GPR : regfile
register PC : word
register MEM : memory
register HALTED : bool

/* The five input lines, held by the drivers for the duration of one step. */
register KEYS : bits(5)

/* Driver scratch: the successor PC proposed by the current instruction. */
register nextPC : word

function rX(r : regidx) -> word = GPR[unsigned(r)]

function wX(r : regidx, value : word) -> unit = {
    GPR[unsigned(r)] = value
}

overload X = {rX, wX}

let lr : regidx = 0b110
let sp : regidx = 0b111

/* "PC 16-bit, +2 per fetch, masked to 0x7FF": every PC write keeps 11 bits. */
function pc_mask(value : word) -> word = 0b00000 @ value[10 .. 0]

/* Byte bus: the low 11 address bits select a byte of the 2 KB memory.
 * "A byte read from 0x5FF returns {3'b000, QUIT, RIGHT, LEFT, DOWN, UP}";
 * a store to 0x5FF still writes the RAM byte, which reads never return. */
let input_port : address = 0b10111111111

function read_byte(addr : word) -> byte = {
    let a : address = addr[10 .. 0];
    if a == input_port then {
        0b000 @ KEYS
    } else {
        MEM[unsigned(a)]
    }
}

function write_byte(addr : word, value : byte) -> unit = {
    MEM[unsigned(addr[10 .. 0])] = value
}

/* Word bus: "word index = addr >> 1, lane = addr[0]", big-endian bytes.
 * A word access ignores address bit 0, and is two byte accesses in effect. */
function read_word(addr : word) -> word =
    read_byte(addr[15 .. 1] @ 0b0) @ read_byte(addr[15 .. 1] @ 0b1)

function write_word(addr : word, value : word) -> unit = {
    write_byte(addr[15 .. 1] @ 0b0, value[15 .. 8]);
    write_byte(addr[15 .. 1] @ 0b1, value[7 .. 0])
}

/* The 64x64 framebuffer at 0x600-0x7FF, one bit per pixel, row 0 at the
 * bottom: "Pixel (x, y): byte = 0x0600 + y*8 + x/8, bit = 7 - (x mod 8)". */
val pixel : (range(0, 63), range(0, 63)) -> bool

function pixel(x, y) = {
    let column : bits(6) = get_slice_int(6, x, 0);
    let row : bits(6) = get_slice_int(6, y, 0);
    let pixels = MEM[unsigned(0b11 @ row @ column[5 .. 3])];
    pixels[7 - unsigned(column[2 .. 0])] == bitone
}
