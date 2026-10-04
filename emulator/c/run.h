/* A run of the machine: stepping it with input lines, counting the retirements, and noticing why
 * it ends. Batch and interactive mode share it, so both end a run the same way.
 *
 * Before each step the run checks, in this order, whether the CPU has halted (the run is
 * halted), and whether the step limit is reached (the run is at its limit). A step that fetches
 * an unassigned opcode ends the run as illegal and does not count as a retirement. */
#ifndef TARA_RUN_H
#define TARA_RUN_H

#include <stdint.h>

#include "machine.h"

/* The exit status of the emulator. */
enum exit_status { EXIT_HALTED = 0, EXIT_ERROR = 1, EXIT_LIMIT = 3, EXIT_ILLEGAL = 4 };

enum run_state { RUN_RUNNING, RUN_HALTED, RUN_LIMIT, RUN_ILLEGAL };

struct run {
  enum run_state state;
  uint64_t retired; /* instructions retired so far */
  uint64_t limit;   /* the retirements after which the run stops; 0: no limit */
};

/* Start a run of the machine as it is now. */
void run_start(struct run *run, uint64_t limit);

/* Execute one instruction with the given input lines, and update the state. The run must be
 * RUNNING. */
enum step_result run_step(struct run *run, uint8_t keys);

/* The state as the status line and the "status" output line spell it. */
const char *run_state_name(enum run_state state);

/* The exit status for a run that ended, or was left, in this state. */
enum exit_status run_exit_status(enum run_state state);

#endif
