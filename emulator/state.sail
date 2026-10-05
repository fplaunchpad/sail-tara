/* State interface shared by the emulators and the SystemVerilog step module. */

$include "../model/tara.sail"

/* The fetch of the most recent host_step, for host_trace. */
register trace_pc : word
register trace_word : word

/* Power-on: registers and memory cleared, the CPU running from PC 0. */
val host_reset : unit -> unit

function host_reset() = {
    GPR = vector_init(8, 0x0000);
    MEM = vector_init(2048, 0x00);
    KEYS = 0b00000;
    trace_pc = 0x0000;
    trace_word = 0x0000;
    reset()
}

/* The memory as the host sees it: RAM bytes, without the input port. */
val host_peek : bits(11) -> bits(8)

function host_peek(addr) = MEM[unsigned(addr)]

val host_poke : (bits(11), bits(8)) -> unit

function host_poke(addr, value) = {
    MEM[unsigned(addr)] = value
}

val host_reg : bits(3) -> bits(16)

function host_reg(r) = X(r)

val host_pc : unit -> bits(16)

function host_pc() = PC

val host_halted : unit -> bool

function host_halted() = HALTED

val host_pixel : (bits(6), bits(6)) -> bool

function host_pixel(x, y) = pixel(unsigned(x), unsigned(y))

/* One step with the given input lines: 0 retired, 1 stopped (the CPU is
 * halted), 2 illegal opcode (PC has advanced past it). */
$[sv_toplevel { name = tara_step, inout_regs = true, finish = false }]
val host_step : bits(5) -> bits(2)

function host_step(keys) = {
    if not_bool(HALTED) then {
        KEYS = keys;
        trace_pc = PC;
        trace_word = read_word(PC)
    };
    match step(keys) {
        Retired() => 0b00,
        Stopped() => 0b01,
        Illegal(_) => 0b10,
    }
}
