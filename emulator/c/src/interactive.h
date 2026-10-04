/* Interactive mode (-i): play the program in the terminal.
 *
 * The screen is the framebuffer (see display.h) above a status line:
 *
 *   <state>  pc 0xPPPP  steps N  keys UDLRQ
 *
 * where the state is running, halted, illegal or limit, and the keys are the held input lines in
 * the order UP DOWN LEFT RIGHT QUIT, each a letter or '-'. Keys are read as input.h describes.
 *
 * The run goes on in frames, about 30 a second: each runs --hz / 30 instructions (as many as fit
 * in the frame for --hz 0) with the input lines held at its start, and then redraws. When the run
 * ends, its last frame stays until the player quits. */
#ifndef TARA_INTERACTIVE_H
#define TARA_INTERACTIVE_H

#include "options.h"

/* Returns the exit status: 0 if the player quit a run that was running or halted, 3 or 4 if it
 * had reached its step limit or fetched an illegal opcode, and 1 for an error, which is
 * reported before the terminal is touched or after it is restored. */
int interactive_run(const struct options *options);

#endif
