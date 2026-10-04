/* The TARA machine: the Sail model, compiled through emulator/host.sail.
 * Hides the generated names and the Sail runtime types from the emulator. */
#ifndef TARA_MACHINE_H
#define TARA_MACHINE_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

/* The framebuffer is SCREEN_SIZE pixels wide and high. */
enum { SCREEN_SIZE = 64 };

enum step_result { STEP_RETIRED = 0, STEP_STOPPED = 1, STEP_ILLEGAL = 2 };

/* Start the model at power-on (registers and memory cleared, PC 0); stop it. */
void start_machine(void);
void stop_machine(void);

/* Write a byte of RAM, as a program loader does. */
void poke_memory(uint16_t address, uint8_t value);

uint16_t machine_pc(void);
bool machine_halted(void);

/* Pixel (x, y) of the framebuffer, from 0 to SCREEN_SIZE - 1; y = 0 is the bottom row. */
bool machine_pixel(unsigned x, unsigned y);

/* Execute one instruction with the given input lines (bits 0-4). */
enum step_result step_machine(uint8_t keys);

/* Print the trace line of the last step, or the final state, to out. */
void print_trace(FILE *out);
void print_dump(FILE *out);

/* Print the assembly text of an instruction word, "illegal" for an unassigned opcode. */
void print_disassembly(FILE *out, uint16_t word);

#endif
