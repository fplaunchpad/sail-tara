#include "options.h"

#include <getopt.h> // IWYU pragma: keep (getopt_long is declared in a private glibc header)
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "keys.h"
#include "number.h"
#include "report.h"

#define DEFAULT_MAX_STEPS 1000000
#define DEFAULT_HZ 2000

static const char USAGE[] =
    "usage: " PROGRAM_NAME " [OPTION...] IMAGE\n"
    "       " PROGRAM_NAME " --disasm-all\n"
    "\n"
    "Run a TARA program on the C build of the Sail model and print the final state. IMAGE is\n"
    "loaded at address 0: a .bin file of raw bytes, or a .hex file of 16-bit words in hex.\n"
    "\n"
    "  -t, --trace         print a line per step: PC, word, registers after it, assembly\n"
    "  -n, --max-steps N   stop after N retirements (default 1000000; 0: no limit)\n"
    "      --keys K        input lines 0-31, decimal or 0x hex (default 0)\n"
    "      --key-script F  change the input lines during the run, \"STEP KEYS\" per line\n"
    "      --fb            print the framebuffer after the final state\n"
    "      --disasm-all    print the assembly of every 16-bit word; takes no IMAGE\n"
    "  -i, --interactive   play in the terminal (no step limit unless -n is given)\n"
    "      --hz N          interactive instructions per second (default 2000; 0: as fast as\n"
    "                      possible)\n"
    "  -h, --help          print this text\n"
    "\n"
    "Exit status: 0 halted, 1 error, 3 step limit, 4 illegal opcode.\n"
    "Interactive: the arrow keys or w, a, s, d and q drive the input lines; Esc or Ctrl-C quits.\n";

/* The options that have no short form. */
enum { OPT_KEYS = 256, OPT_KEY_SCRIPT, OPT_FB, OPT_DISASM_ALL, OPT_HZ };

static const char SHORT_OPTIONS[] = "tn:ih";

static const struct option LONG_OPTIONS[] = {
    {"trace", no_argument, NULL, 't'},
    {"max-steps", required_argument, NULL, 'n'},
    {"keys", required_argument, NULL, OPT_KEYS},
    {"key-script", required_argument, NULL, OPT_KEY_SCRIPT},
    {"fb", no_argument, NULL, OPT_FB},
    {"disasm-all", no_argument, NULL, OPT_DISASM_ALL},
    {"interactive", no_argument, NULL, 'i'},
    {"hz", required_argument, NULL, OPT_HZ},
    {"help", no_argument, NULL, 'h'},
    {NULL, 0, NULL, 0},
};

/* Which options were given, for the checks that need more than their values. */
struct given {
  bool max_steps, keys, interactive, disasm_all;
  bool others; /* an option other than --disasm-all */
};

/* Apply an option getopt_long found. Reports a bad value. */
static bool apply(struct options *options, struct given *given, int option, const char *argument) {
  switch (option) {
  case 't':
    options->trace = true;
    return true;
  case 'n':
    given->max_steps = true;
    if (!parse_decimal(argument, UINT64_MAX, &options->max_steps)) {
      return report_error("--max-steps: '%s' is not a count (decimal digits)", argument);
    }
    return true;
  case OPT_KEYS:
    given->keys = true;
    if (!keys_parse(argument, &options->keys)) {
      return report_error("--keys: '%s' is not input lines (0-%u, decimal or 0x hex)", argument,
                          KEYS_MAX);
    }
    return true;
  case OPT_KEY_SCRIPT:
    options->key_script = argument;
    return true;
  case OPT_FB:
    options->framebuffer = true;
    return true;
  case OPT_DISASM_ALL:
    given->disasm_all = true;
    return true;
  case 'i':
    given->interactive = true;
    return true;
  case OPT_HZ:
    if (!parse_decimal(argument, UINT64_MAX, &options->hz)) {
      return report_error("--hz: '%s' is not a rate (decimal digits)", argument);
    }
    return true;
  default:
    return report_error("option %d is not handled", option);
  }
}

/* Interactive mode plays a program: it prints no trace, framebuffer or final state, the input
 * lines come from the player, and it runs without a step limit unless -n gives one. */
static bool check_interactive(struct options *options, const struct given *given) {
  const struct {
    const char *name;
    bool given;
  } batch_only[] = {
      {"--trace", options->trace},
      {"--fb", options->framebuffer},
      {"--keys", given->keys},
      {"--key-script", options->key_script != NULL},
  };
  for (size_t i = 0; i < sizeof batch_only / sizeof *batch_only; ++i) {
    if (batch_only[i].given) {
      return report_error("%s cannot be used with --interactive", batch_only[i].name);
    }
  }

  if (!given->max_steps) {
    options->max_steps = 0;
  }
  return true;
}

/* Check what getopt_long cannot: the options that do not go together, and the operands. */
static bool check(struct options *options, const struct given *given, int operands,
                  char *const operand[]) {
  if (given->disasm_all) {
    if (given->others) {
      return report_error("--disasm-all cannot be combined with other options");
    }
    if (operands > 0) {
      return report_error("--disasm-all takes no IMAGE");
    }
    options->mode = MODE_DISASM;
    return true;
  }

  if (operands == 0) {
    return report_error("missing IMAGE");
  }
  if (operands > 1) {
    return report_error("unexpected argument '%s'", operand[1]);
  }
  options->image = operand[0];
  if (!given->interactive) {
    return true;
  }
  options->mode = MODE_INTERACTIVE;
  return check_interactive(options, given);
}

static enum options_result fail(void) {
  fputs("Try '" PROGRAM_NAME " --help' for more information.\n", stderr);
  return OPTIONS_ERROR;
}

enum options_result options_parse(int argc, char *argv[], struct options *options) {
  *options = (struct options){.mode = MODE_BATCH, .max_steps = DEFAULT_MAX_STEPS, .hz = DEFAULT_HZ};
  struct given given = {0};

  static char program_name[] = PROGRAM_NAME;
  argv[0] = program_name; /* getopt_long names the program in its own messages */
  /* getopt_long keeps global state, so it is not thread safe; options are parsed once, first. */
  // NOLINTNEXTLINE(concurrency-mt-unsafe)
  for (int option; (option = getopt_long(argc, argv, SHORT_OPTIONS, LONG_OPTIONS, NULL)) != -1;) {
    if (option == 'h') {
      return OPTIONS_HELP;
    }
    if (option == '?' || !apply(options, &given, option, optarg)) {
      return fail();
    }
    if (option != OPT_DISASM_ALL) {
      given.others = true;
    }
  }
  return check(options, &given, argc - optind, argv + optind) ? OPTIONS_OK : fail();
}

void options_print_usage(FILE *out) { fputs(USAGE, out); }
