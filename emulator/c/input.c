#include "input.h"

#include <ctype.h>

#include "clock.h"

/* A line stays held this long after its key was last pressed; a key held down repeats faster. */
#define HOLD_NS (150 * NS_PER_MS)
/* An ESC alone this long is not the start of a sequence. */
#define ESCAPE_NS (20 * NS_PER_MS)

#define ESC 0x1b
#define CTRL_C 0x03
#define NO_LINE (-1)

void input_init(struct input *input) {
  *input = (struct input){.state = INPUT_GROUND};
  for (int line = 0; line < KEY_LINES; ++line)
    input->held_until[line] = INT64_MIN;
}

/* The line a letter key drives, or NO_LINE. */
static int letter_line(uint8_t key) {
  switch (tolower(key)) {
  case 'w':
    return KEY_UP;
  case 's':
    return KEY_DOWN;
  case 'a':
    return KEY_LEFT;
  case 'd':
    return KEY_RIGHT;
  case 'q':
    return KEY_QUIT;
  default:
    return NO_LINE;
  }
}

/* The line an arrow key drives, by the final byte of its sequence, or NO_LINE. */
static int arrow_line(uint8_t final) {
  switch (final) {
  case 'A':
    return KEY_UP;
  case 'B':
    return KEY_DOWN;
  case 'C':
    return KEY_RIGHT;
  case 'D':
    return KEY_LEFT;
  default:
    return NO_LINE;
  }
}

static void press(struct input *input, int line, int64_t now) {
  if (line != NO_LINE)
    input->held_until[line] = now + HOLD_NS;
}

/* Inside ESC [ or ESC O, parameter and intermediate bytes go on and a final byte ends the
 * sequence. Returns true if the byte belongs to the sequence. */
static bool feed_sequence_byte(struct input *input, uint8_t byte, int64_t now) {
  if (byte >= 0x20 && byte <= 0x3F)
    return true;
  if (byte < 0x40 || byte > 0x7E)
    return false;

  press(input, arrow_line(byte), now);
  input->state = INPUT_GROUND;
  return true;
}

/* Returns true if the byte is Ctrl-C, or an ESC that begins no sequence. */
static bool feed_byte(struct input *input, uint8_t byte, int64_t now) {
  if (input->state == INPUT_SEQUENCE) {
    if (feed_sequence_byte(input, byte, now))
      return false;
    input->state = INPUT_GROUND; /* not part of the sequence: a key of its own */
  }

  switch (input->state) {
  case INPUT_GROUND:
    if (byte == ESC)
      input->state = INPUT_ESCAPE;
    else if (byte == CTRL_C)
      return true;
    else
      press(input, letter_line(byte), now);
    return false;
  case INPUT_ESCAPE:
    if (byte != '[' && byte != 'O')
      return true;
    input->state = INPUT_SEQUENCE;
    return false;
  case INPUT_SEQUENCE:
    break;
  }
  return false;
}

bool input_feed(struct input *input, const uint8_t *bytes, size_t length, int64_t now) {
  for (size_t i = 0; i < length; ++i) {
    if (feed_byte(input, bytes[i], now))
      return true;
  }
  if (input->state != INPUT_GROUND)
    input->pending_since = now;
  return false;
}

int64_t input_deadline(const struct input *input) {
  return input->state == INPUT_GROUND ? INT64_MAX : input->pending_since + ESCAPE_NS;
}

bool input_expire(struct input *input, int64_t now) {
  if (now < input_deadline(input))
    return false;
  input->state = INPUT_GROUND;
  return true;
}

uint8_t input_held(const struct input *input, int64_t now) {
  uint8_t keys = 0;
  for (int line = 0; line < KEY_LINES; ++line) {
    if (now < input->held_until[line])
      keys |= (uint8_t)(1u << line);
  }
  return keys;
}
