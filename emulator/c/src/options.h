/* The command line. */
#ifndef TARA_OPTIONS_H
#define TARA_OPTIONS_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

enum mode { MODE_BATCH, MODE_INTERACTIVE, MODE_DISASM };

struct options {
  enum mode mode;
  bool trace;             /* -t: print the trace line of each step */
  bool framebuffer;       /* --fb: print the framebuffer after the final state */
  uint64_t max_steps;     /* -n: retirements before the run stops; 0: no limit */
  uint8_t keys;           /* --keys: the input lines before the key script changes them */
  const char *key_script; /* --key-script: the script file, or NULL */
  uint64_t hz;            /* --hz: interactive instructions per second; 0: as fast as possible */
  const char *image;      /* IMAGE; NULL in MODE_DISASM */
};

enum options_result { OPTIONS_OK, OPTIONS_HELP, OPTIONS_ERROR };

/* Parse the command line into options. On OPTIONS_ERROR, print why to stderr. */
enum options_result parse_options(int argc, char *argv[], struct options *options);

void print_usage(FILE *out);

#endif
