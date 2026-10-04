#include "options.h"

#include <getopt.h> // IWYU pragma: keep (getopt_long is declared in a private glibc header)
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "keys.h"
#include "number.h"
#include "report.h"

#define DEFAULT_MAX_STEPS 1000000
#define DEFAULT_HZ 2000

static const char USAGE[] =
    "usage: " PROGRAM_NAME " run [OPTION...] IMAGE\n"
    "       " PROGRAM_NAME " play [OPTION...] IMAGE\n"
    "       " PROGRAM_NAME " disasm\n"
    "\n"
    "Run TARA programs on the C build of the Sail model. IMAGE is loaded at address 0: a .bin\n"
    "file of raw bytes, or a .hex file of 16-bit words in hex.\n"
    "\n"
    "  run     run a program to its end and print what happened\n"
    "  play    play a program in the terminal\n"
    "  disasm  print the assembly of every 16-bit word\n"
    "\n"
    "'" PROGRAM_NAME " SUBCOMMAND --help' lists the options of a subcommand.\n"
    "Exit status: 0 halted, 1 error, 3 step limit, 4 illegal opcode.\n";

static const char RUN_USAGE[] =
    "usage: " PROGRAM_NAME " run [OPTION...] IMAGE\n"
    "\n"
    "Run the program to its end, then print its status, its steps and the final state.\n"
    "\n"
    "  -t, --trace            print a line per step: PC, word, registers after it, assembly\n"
    "  -n, --max-steps N      stop after N retirements (default 1000000; 0: no limit)\n"
    "      --keys K           input lines 0-31, decimal or 0x hex (default 0)\n"
    "      --key-script FILE  change the input lines during the run, \"STEP KEYS\" per line\n"
    "      --framebuffer      print the framebuffer after the final state\n"
    "  -h, --help             print this text\n";

static const char PLAY_USAGE[] =
    "usage: " PROGRAM_NAME " play [OPTION...] IMAGE\n"
    "\n"
    "Play the program in the terminal. The arrow keys or w, a, s, d and q drive the input lines;\n"
    "Esc or Ctrl-C quits.\n"
    "\n"
    "  -n, --max-steps N  stop after N retirements (default: no limit)\n"
    "      --hz N         instructions per second (default 2000; 0: as fast as possible)\n"
    "  -h, --help         print this text\n";

static const char DISASM_USAGE[] =
    "usage: " PROGRAM_NAME " disasm\n"
    "\n"
    "Print the assembly of every 16-bit word, 0000 to ffff, one \"WWWW TEXT\" line each.\n"
    "\n"
    "  -h, --help  print this text\n";

/* The codes getopt_long returns for the options that have no short form; the others return their
 * short form. Every spelling of an option returns the same code. */
enum { OPT_KEYS = 256, OPT_KEY_SCRIPT, OPT_FRAMEBUFFER, OPT_HZ, OPT_CODES };

static const struct option RUN_OPTIONS[] = {
    {"trace", no_argument, NULL, 't'},
    {"max-steps", required_argument, NULL, 'n'},
    {"keys", required_argument, NULL, OPT_KEYS},
    {"key-script", required_argument, NULL, OPT_KEY_SCRIPT},
    {"framebuffer", no_argument, NULL, OPT_FRAMEBUFFER},
    {"help", no_argument, NULL, 'h'},
    {NULL, 0, NULL, 0},
};

static const struct option PLAY_OPTIONS[] = {
    {"max-steps", required_argument, NULL, 'n'},
    {"hz", required_argument, NULL, OPT_HZ},
    {"help", no_argument, NULL, 'h'},
    {NULL, 0, NULL, 0},
};

static const struct option DISASM_OPTIONS[] = {
    {"help", no_argument, NULL, 'h'},
    {NULL, 0, NULL, 0},
};

/* A subcommand's name, its help, and the options and operands it takes. */
struct syntax {
  const char *name;
  enum subcommand subcommand;
  const char *usage;
  const char *short_options;
  const struct option *long_options;
  int operands; /* 1: IMAGE; 0: none */
};

static const struct syntax SUBCOMMANDS[] = {
    {"run", SUBCOMMAND_RUN, RUN_USAGE, "tn:h", RUN_OPTIONS, 1},
    {"play", SUBCOMMAND_PLAY, PLAY_USAGE, "n:h", PLAY_OPTIONS, 1},
    {"disasm", SUBCOMMAND_DISASM, DISASM_USAGE, "h", DISASM_OPTIONS, 0},
};

static const struct syntax *find_subcommand(const char *name) {
  for (size_t i = 0; i < sizeof SUBCOMMANDS / sizeof *SUBCOMMANDS; ++i) {
    if (strcmp(SUBCOMMANDS[i].name, name) == 0) {
      return &SUBCOMMANDS[i];
    }
  }
  return NULL;
}

static bool is_subcommand_prefix(const char *name) {
  size_t length = strlen(name);
  if (length == 0) {
    return false;
  }
  for (size_t i = 0; i < sizeof SUBCOMMANDS / sizeof *SUBCOMMANDS; ++i) {
    if (strncmp(SUBCOMMANDS[i].name, name, length) == 0) {
      return true;
    }
  }
  return false;
}

static bool parse_count(const char *option, const char *argument, uint64_t *count) {
  if (!parse_decimal(argument, UINT64_MAX, count)) {
    return report_error("%s: '%s' is not a count (decimal digits)", option, argument);
  }
  return true;
}

/* Apply an option that getopt_long found; the subcommand's table admits only its own. Reports a
 * bad value. */
static bool apply(struct command *command, int option, const char *argument) {
  switch (option) {
  case 't':
    command->run.trace = true;
    return true;
  case 'n':
    if (command->subcommand == SUBCOMMAND_PLAY) {
      return parse_count("--max-steps", argument, &command->play.max_steps);
    }
    return parse_count("--max-steps", argument, &command->run.max_steps);
  case OPT_KEYS:
    if (!parse_keys(argument, &command->run.keys)) {
      return report_error("--keys: '%s' is not input lines (0-%u, decimal or 0x hex)", argument,
                          KEYS_MAX);
    }
    return true;
  case OPT_KEY_SCRIPT:
    command->run.key_script = argument;
    return true;
  case OPT_FRAMEBUFFER:
    command->run.framebuffer = true;
    return true;
  case OPT_HZ:
    return parse_count("--hz", argument, &command->play.hz);
  default:
    return report_error("option %d is not handled", option);
  }
}

/* The long spelling of the option getopt_long returned as `code`. */
static const char *long_name(const struct syntax *syntax, int code) {
  for (const struct option *option = syntax->long_options; option->name; ++option) {
    if (option->val == code) {
      return option->name;
    }
  }
  return "option";
}

/* The operands after the options: IMAGE, or none. */
static bool take_operands(struct command *command, const struct syntax *syntax, int count,
                          char *const operand[]) {
  if (count > syntax->operands) {
    return report_error("%s: unexpected argument '%s'", syntax->name, operand[syntax->operands]);
  }
  if (count < syntax->operands) {
    return report_error("%s: missing IMAGE", syntax->name);
  }

  if (command->subcommand == SUBCOMMAND_RUN) {
    command->run.image = operand[0];
  } else if (command->subcommand == SUBCOMMAND_PLAY) {
    command->play.image = operand[0];
  }
  return true;
}

static const struct parse_result HELP = {.status = PARSE_HELP};
static const struct parse_result ERROR = {.status = PARSE_ERROR};

static struct parse_result fail(void) {
  fputs("Try '" PROGRAM_NAME " --help' for more information.\n", stderr);
  return ERROR;
}

static struct parse_result parse_help(int argc, char *argv[]) {
  if (argc == 2) {
    fputs(USAGE, stdout);
    return HELP;
  }
  if (argc == 3) {
    const struct syntax *syntax = find_subcommand(argv[2]);
    if (syntax != NULL) {
      fputs(syntax->usage, stdout);
      return HELP;
    }
    if (is_subcommand_prefix(argv[2])) {
      report_error("'%s' is not a subcommand: run, play or disasm", argv[2]);
      return fail();
    }
  }
  report_error("unexpected argument after --help");
  return fail();
}

/* A command for the subcommand, with its options at their defaults. */
static struct command default_command(enum subcommand subcommand) {
  switch (subcommand) {
  case SUBCOMMAND_RUN:
    return (struct command){.subcommand = subcommand, .run = {.max_steps = DEFAULT_MAX_STEPS}};
  case SUBCOMMAND_PLAY:
    return (struct command){.subcommand = subcommand, .play = {.max_steps = 0, .hz = DEFAULT_HZ}};
  case SUBCOMMAND_DISASM:
    break;
  }
  return (struct command){.subcommand = subcommand};
}

struct parse_result parse_command_line(int argc, char *argv[]) {
  if (argc < 2) {
    report_error("missing subcommand: run, play or disasm");
    return fail();
  }
  if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
    return parse_help(argc, argv);
  }

  const struct syntax *syntax = find_subcommand(argv[1]);
  if (!syntax) {
    report_error("'%s' is not a subcommand: run, play or disasm", argv[1]);
    return fail();
  }
  struct command command = default_command(syntax->subcommand);
  bool seen[OPT_CODES] = {false}; /* by option code */

  /* The subcommand's arguments follow its name, which getopt_long takes for the program's name
   * in its own messages. */
  static char program_name[] = PROGRAM_NAME;
  argv[1] = program_name;
  int count = argc - 1;
  char **arguments = argv + 1;
  /* getopt_long keeps global state, so it is not thread safe; options are parsed once, first. */
  // NOLINTNEXTLINE(concurrency-mt-unsafe)
  for (int option; (option = getopt_long(count, arguments, syntax->short_options,
                                         syntax->long_options, NULL)) != -1;) {
    if (option == 'h') {
      fputs(syntax->usage, stdout);
      return HELP;
    }
    if (option == '?') {
      return fail();
    }
    if (seen[option]) {
      report_error("--%s may only be specified once", long_name(syntax, option));
      return fail();
    }
    seen[option] = true;
    if (!apply(&command, option, optarg)) {
      return fail();
    }
  }
  if (!take_operands(&command, syntax, count - optind, arguments + optind)) {
    return fail();
  }
  return (struct parse_result){.status = PARSE_OK, .command = command};
}
