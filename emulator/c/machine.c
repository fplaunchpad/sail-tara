#include "machine.h"

#include "sail.h"
#include "tara.h"

/* Defined by the generated model, but not declared in tara.h. */
void model_init(void);
void model_fini(void);

void machine_start(void) {
  model_init();
  zhost_reset(UNIT);
}

void machine_stop(void) { model_fini(); }

void machine_poke(uint16_t address, uint8_t value) { zhost_poke(address, value); }

bool machine_halted(void) { return zhost_halted(UNIT); }

enum step_result machine_step(uint8_t keys) { return (enum step_result)zhost_step(keys); }

/* Print a string made by the host interface, then free it. */
static void print_text(FILE *out, void (*text)(sail_string *, unit)) {
  sail_string s;
  CREATE(sail_string)(&s);
  text(&s, UNIT);
  fputs(s, out);
  KILL(sail_string)(&s);
}

void machine_print_trace(FILE *out) {
  print_text(out, zhost_trace);
  fputc('\n', out);
}

void machine_print_dump(FILE *out) { print_text(out, zhost_dump); }
