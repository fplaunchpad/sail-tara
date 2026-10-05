# Verilator emulator

`tara-verilator` executes `emulator/state.sail`'s `host_step` through Sail-generated
SystemVerilog and Verilator 5.052. The combinational `tara_step` module takes and returns the
complete machine state. The shared native frontend uses Sail's C output for initialization,
image loading, disassembly and text formatting.

## Sail backend patch

[sail-sv-reachability.patch](../../nix/patches/sail-sv-reachability.patch) changes only Sail
0.20.3's SystemVerilog backend. Its original translation repeatedly expands path conditions
at control-flow joins in the generated instruction codec. The patch emits a boolean signal
for each block's reachability, computed from its predecessors and branch guard. Phi inputs
and assertions use those signals. This preserves the branch conditions while sharing them
across joins. Assertions remain enabled.

Generation disables Sail's SystemVerilog optimization passes so they do not expand these
signals again. Verilator optimizes the resulting circuit. Unions are emitted as structs;
the state ports use fixed arrays, and Sail's dynamic memory implementation is disabled.

The Nix scope also builds the locked Verilator release with C++17 to match the SystemC
library's API version in its own smoke tests. The authored emulator adapter uses C++23.
