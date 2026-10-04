#include "keys.h"

#include "number.h"
#include <stdint.h>

/* The letter that spells each line, in the order of enum key_line. */
#define KEY_LETTERS "UDLRQ"

bool keys_parse(const char *text, uint8_t *keys) {
  uint64_t value;
  if (!parse_decimal_or_hex(text, KEYS_MAX, &value)) {
    return false;
  }
  *keys = (uint8_t)value;
  return true;
}

void keys_spell(uint8_t keys, char spelling[KEY_LINES + 1]) {
  for (int line = 0; line < KEY_LINES; ++line) {
    bool held = (keys >> line) & 1;
    spelling[line] = (char)(held ? KEY_LETTERS[line] : '-');
  }
  spelling[KEY_LINES] = '\0';
}
