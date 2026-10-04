/* Batch mode: run an image to the end of the run and print what happened.
 *
 * The output, in order: the trace lines (with -t), "status halted|limit|illegal", "steps N" (the
 * retirements), the machine's dump, and the framebuffer lines (with --fb). */
#ifndef TARA_BATCH_H
#define TARA_BATCH_H

#include "options.h"

/* Returns the exit status: 0 halted, 3 step limit, 4 illegal opcode, 1 for an error, in which
 * case nothing was printed on standard output. */
int run_batch(const struct options *options);

#endif
