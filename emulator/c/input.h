/* Keys typed in the terminal, as the machine's input lines.
 *
 *   arrows        UP, DOWN, LEFT, RIGHT: ESC [ A/B/D/C or ESC O A/B/D/C
 *   w s a d       the same four lines, in either case
 *   q             QUIT (an input line of the program, not the emulator's quit)
 *   Esc, Ctrl-C   quit the emulator; Esc has to be alone, see input_expire
 *
 * Terminals report presses but no releases, so a line stays held for a while after the last press
 * of its key. Times are in nanoseconds on any monotonic clock. */
#ifndef TARA_INPUT_H
#define TARA_INPUT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "keys.h"

enum input_state {
  INPUT_GROUND,   /* between keys */
  INPUT_ESCAPE,   /* after ESC */
  INPUT_SEQUENCE, /* inside ESC [ or ESC O, up to the final byte */
};

struct input {
  enum input_state state;
  int64_t pending_since;         /* when the last byte of the unfinished sequence came in */
  int64_t held_until[KEY_LINES]; /* when each input line is released */
};

void input_init(struct input *input);

/* Take in bytes read at time `now`. Returns true if the player asked to quit. */
bool input_feed(struct input *input, int64_t now, const uint8_t *bytes, size_t length);

/* An ESC, or the start of a sequence, that nothing follows within a few milliseconds is a key of
 * its own: ESC quits. When there is nothing unfinished, input_deadline is INT64_MAX. Otherwise it
 * is the time from which input_expire reports that the player quit. */
int64_t input_deadline(const struct input *input);
bool input_expire(struct input *input, int64_t now);

/* The input lines held at time `now`. */
uint8_t input_held(const struct input *input, int64_t now);

#endif
