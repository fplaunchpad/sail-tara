/* TARA emulator: the C build of the Sail model.
 *
 * Run a program image from address 0 and print the final state (batch mode), play it in the
 * terminal (-i), or print the disassembly of every word (--disasm-all). Run `tara-c --help` for
 * the command line.
 *
 * Exit status: 0 halted, 1 error (usage, image, key script, terminal), 3 step limit, 4 illegal
 * opcode. An error prints a message on stderr and nothing on stdout.
 *
 * The modules: options (the command line); image and keyscript (what a run loads); run (the
 * stepping both modes share); batch and disasm (the printed outputs); interactive, with terminal,
 * input and display (playing in the terminal); machine (the Sail model); report, number, keys and
 * clock (small helpers).
 */
#include <stdlib.h>

#include "batch.h"
#include "disasm.h"
#include "interactive.h"
#include "machine.h"
#include "options.h"
#include "run.h"

static int run_mode(const struct options *options) {
  switch (options->mode) {
  case MODE_BATCH:
    return batch_run(options);
  case MODE_INTERACTIVE:
    return interactive_run(options);
  case MODE_DISASM:
    return disasm_run();
  }
  return EXIT_ERROR;
}

int main(int argc, char *argv[]) {
  struct options options;
  switch (options_parse(argc, argv, &options)) {
  case OPTIONS_OK:
    break;
  case OPTIONS_HELP:
    options_print_usage(stdout);
    return EXIT_SUCCESS;
  case OPTIONS_ERROR:
    return EXIT_ERROR;
  }

  machine_start();
  int status = run_mode(&options);
  machine_stop();
  return status;
}
