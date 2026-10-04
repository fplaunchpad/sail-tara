/* TARA emulator: the C build of the Sail model.
 *
 * Run a program image from address 0 and print the final state (tara-c run), play it in the
 * terminal (tara-c play), or print the disassembly of every word (tara-c disasm). Run
 * `tara-c --help` for the command line.
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

/* Run the subcommand, and return the exit status. */
static int run_subcommand(const struct command *command) {
  switch (command->subcommand) {
  case SUBCOMMAND_RUN:
    return run_batch(&command->run);
  case SUBCOMMAND_PLAY:
    return run_interactive(&command->play);
  case SUBCOMMAND_DISASM:
    return disassemble_all();
  }
  return EXIT_ERROR;
}

int main(int argc, char *argv[]) {
  struct command command;
  switch (parse_command_line(argc, argv, &command)) {
  case PARSE_OK:
    break;
  case PARSE_HELP:
    return EXIT_SUCCESS;
  case PARSE_ERROR:
    return EXIT_ERROR;
  }

  start_machine();
  int status = run_subcommand(&command);
  stop_machine();
  return status;
}
