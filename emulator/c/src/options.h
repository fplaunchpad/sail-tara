/* The command line: a subcommand and its options.
 *
 *   tara-c run [OPTION...] IMAGE   run a program to its end and print what happened
 *   tara-c play [OPTION...] IMAGE  play a program in the terminal
 *   tara-c disasm                  print the assembly of every 16-bit word
 *
 * Each subcommand takes only its own options, so no option needs checking against another. */
#ifndef TARA_OPTIONS_H
#define TARA_OPTIONS_H

#include <stdbool.h>
#include <stdint.h>

enum subcommand { SUBCOMMAND_RUN, SUBCOMMAND_PLAY, SUBCOMMAND_DISASM };

/* run: an image to the end of the run. */
struct run_options {
  bool trace;             /* -t: print the trace line of each step */
  bool framebuffer;       /* --framebuffer: print the framebuffer after the final state */
  uint64_t max_steps;     /* -n: retirements before the run stops; 0: no limit */
  uint8_t keys;           /* --keys: the input lines before the key script changes them */
  const char *key_script; /* --key-script: the script file, or NULL */
  const char *image;
};

/* play: an image in the terminal. */
struct play_options {
  uint64_t max_steps; /* -n: retirements before the run stops; 0 (the default): no limit */
  uint64_t hz;        /* --hz: instructions per second; 0: as fast as possible */
  const char *image;
};

struct command {
  enum subcommand subcommand;
  struct run_options run;   /* for SUBCOMMAND_RUN */
  struct play_options play; /* for SUBCOMMAND_PLAY */
};

enum parse_result { PARSE_OK, PARSE_HELP, PARSE_ERROR };

/* Parse the command line. PARSE_HELP: the help that was asked for has been printed on standard
 * output. PARSE_ERROR: why has been printed on standard error. */
enum parse_result parse_command_line(int argc, char *argv[], struct command *command);

#endif
