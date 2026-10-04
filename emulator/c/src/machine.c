#include "machine.h"

#include "sail.h"
#include "tara.h"
#include <stdint.h>
#include <stdio.h>

/* Defined by the generated model, but not declared in tara.h. */
void model_init(void);
void model_fini(void);

void start_machine(void) {
  model_init();
  zhost_reset(UNIT);
}

void stop_machine(void) { model_fini(); }

void poke_memory(uint16_t address, uint8_t value) { zhost_poke(address, value); }

uint16_t machine_pc(void) { return (uint16_t)zhost_pc(UNIT); }

bool machine_halted(void) { return zhost_halted(UNIT); }

bool machine_pixel(unsigned x, unsigned y) { return zhost_pixel(x, y); }

enum step_result step_machine(uint8_t keys) { return (enum step_result)zhost_step(keys); }

/* Print a string made by the host interface, then free it. */
static void print_text(FILE *out, void (*text)(sail_string *, unit)) {
  sail_string string;
  CREATE(sail_string)(&string);
  text(&string, UNIT);
  fputs(string, out);
  KILL(sail_string)(&string);
}

void print_trace(FILE *out) {
  print_text(out, zhost_trace);
  fputc('\n', out);
}

void print_dump(FILE *out) { print_text(out, zhost_dump); }

void print_disassembly(FILE *out, uint16_t word) {
  sail_string string;
  CREATE(sail_string)(&string);
  zhost_disasm(&string, word);
  fputs(string, out);
  KILL(sail_string)(&string);
}
