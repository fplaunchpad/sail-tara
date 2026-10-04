default Order dec
$include <prelude.sail>

register MEM : bits(8)

function read_mem() -> bits(8) = { MEM }

function write_mem(value : bits(8)) -> unit = { MEM = value }
