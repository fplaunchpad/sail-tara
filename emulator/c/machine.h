/* The TARA machine: the Sail model, compiled through emulator/host.sail.
 * Hides the generated names and the Sail runtime types from the emulator. */
#ifndef TARA_MACHINE_H
#define TARA_MACHINE_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

enum step_result { STEP_RETIRED = 0, STEP_STOPPED = 1, STEP_ILLEGAL = 2 };

/* Start the model at power-on (registers and memory cleared, PC 0); stop it. */
void machine_start(void);
void machine_stop(void);

/* Write a byte of RAM, as a program loader does. */
void machine_poke(uint16_t address, uint8_t value);

bool machine_halted(void);

/* Execute one instruction with the given input lines (bits 0-4). */
enum step_result machine_step(uint8_t keys);

/* Print the trace line of the last step, or the final state, to out. */
void machine_print_trace(FILE *out);
void machine_print_dump(FILE *out);

#endif
