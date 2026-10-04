/* TARA emulator: the C build of the Sail model.
 *
 * Usage: tara-c [-t] [-n MAX_STEPS] IMAGE
 *
 * Loads IMAGE (see image.h) and runs it until the CPU halts, MAX_STEPS
 * instructions retire (default 1000000; 0 means no limit), or an illegal
 * opcode is fetched. With -t, prints a trace line per step. Then prints the
 * final state as "status", "steps" and the machine's dump. Exit status: 0
 * halted, 1 error (usage or image), 3 step limit, 4 illegal opcode.
 */
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "image.h"
#include "machine.h"

#define DEFAULT_MAX_STEPS 1000000

/* Why a run ended; also the exit status. */
enum outcome { HALTED = 0, LIMIT = 3, ILLEGAL = 4 };
#define EXIT_ERROR 1

struct options {
  bool trace;
  uint64_t max_steps;
  const char *image;
};

static const char *outcome_name(enum outcome outcome) {
  switch (outcome) {
  case HALTED:
    return "halted";
  case LIMIT:
    return "limit";
  case ILLEGAL:
    return "illegal";
  }
  return "?";
}

/* Parse a non-negative decimal count. */
static bool parse_count(const char *text, uint64_t *count) {
  char *end;
  errno = 0;
  *count = strtoull(text, &end, 10);
  return errno == 0 && end != text && *end == '\0' && text[0] != '-';
}

static bool parse_options(int argc, char *argv[], struct options *options) {
  *options = (struct options){.trace = false, .max_steps = DEFAULT_MAX_STEPS};
  for (int option; (option = getopt(argc, argv, "tn:")) != -1;) {
    switch (option) {
    case 't':
      options->trace = true;
      break;
    case 'n':
      if (!parse_count(optarg, &options->max_steps))
        return false;
      break;
    default:
      return false;
    }
  }
  if (optind != argc - 1)
    return false;
  options->image = argv[optind];
  return true;
}

/* Step the machine until the run ends; count the retired instructions. */
static enum outcome run(const struct options *options, uint64_t *steps) {
  for (*steps = 0;; ++*steps) {
    if (machine_halted())
      return HALTED;
    if (options->max_steps && *steps == options->max_steps)
      return LIMIT;

    enum step_result result = machine_step(0);
    if (result == STEP_STOPPED)
      return HALTED;
    if (options->trace)
      machine_print_trace(stdout);
    if (result == STEP_ILLEGAL)
      return ILLEGAL;
  }
}

int main(int argc, char *argv[]) {
  struct options options;
  if (!parse_options(argc, argv, &options)) {
    fputs("usage: tara-c [-t] [-n MAX_STEPS] IMAGE\n", stderr);
    return EXIT_ERROR;
  }

  machine_start();
  if (!image_load(options.image)) {
    machine_stop();
    return EXIT_ERROR;
  }

  uint64_t steps;
  enum outcome outcome = run(&options, &steps);
  printf("status %s\nsteps %" PRIu64 "\n", outcome_name(outcome), steps);
  machine_print_dump(stdout);
  machine_stop();
  return outcome;
}
