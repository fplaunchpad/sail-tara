#include "run.h"
#include "machine.h"

#include <assert.h>
#include <stdint.h>

/* The checks made before each step. */
static void settle(struct run *run) {
  if (machine_halted()) {
    run->state = RUN_HALTED;
  } else if (run->limit && run->retired == run->limit) {
    run->state = RUN_LIMIT;
  }
}

void run_start(struct run *run, uint64_t limit) {
  *run = (struct run){.state = RUN_RUNNING, .limit = limit};
  settle(run);
}

enum step_result run_step(struct run *run, uint8_t keys) {
  assert(run->state == RUN_RUNNING);

  enum step_result result = machine_step(keys);
  if (result == STEP_RETIRED) {
    ++run->retired;
  }
  if (result == STEP_ILLEGAL) {
    run->state = RUN_ILLEGAL;
  } else {
    settle(run);
  }
  return result;
}

const char *run_state_name(enum run_state state) {
  switch (state) {
  case RUN_RUNNING:
    return "running";
  case RUN_HALTED:
    return "halted";
  case RUN_LIMIT:
    return "limit";
  case RUN_ILLEGAL:
    return "illegal";
  }
  return "?";
}

enum exit_status run_exit_status(enum run_state state) {
  switch (state) {
  case RUN_RUNNING:
  case RUN_HALTED:
    return EXIT_HALTED;
  case RUN_LIMIT:
    return EXIT_LIMIT;
  case RUN_ILLEGAL:
    return EXIT_ILLEGAL;
  }
  return EXIT_ERROR;
}
