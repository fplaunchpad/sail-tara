#include "number.h"

#include <stdint.h>
#include <string.h>

#define DECIMAL_BASE 10
#define HEX_BASE 16
#define HEX_PREFIX_LENGTH 2

/* The value of the hex digits 'a' and 'A'. */
#define FIRST_LETTER_VALUE 10

int hex_digit_value(int character) {
  if (character >= '0' && character <= '9') {
    return character - '0';
  }
  if (character >= 'a' && character <= 'f') {
    return character - 'a' + FIRST_LETTER_VALUE;
  }
  if (character >= 'A' && character <= 'F') {
    return character - 'A' + FIRST_LETTER_VALUE;
  }
  return -1;
}

/* Parse one or more digits of the given base, rejecting a value that exceeds max before it
 * overflows. */
static bool parse_digits(const char *text, unsigned base, uint64_t max, uint64_t *value) {
  if (*text == '\0') {
    return false;
  }

  uint64_t result = 0;
  for (; *text; ++text) {
    int digit = hex_digit_value((unsigned char)*text);
    if (digit < 0 || (unsigned)digit >= base) {
      return false;
    }
    if ((uint64_t)digit > max || result > (max - (uint64_t)digit) / base) {
      return false;
    }
    result = (result * base) + (uint64_t)digit;
  }
  *value = result;
  return true;
}

bool parse_decimal(const char *text, uint64_t max, uint64_t *value) {
  return parse_digits(text, DECIMAL_BASE, max, value);
}

bool parse_decimal_or_hex(const char *text, uint64_t max, uint64_t *value) {
  if (strncmp(text, "0x", HEX_PREFIX_LENGTH) == 0 || strncmp(text, "0X", HEX_PREFIX_LENGTH) == 0) {
    return parse_digits(text + HEX_PREFIX_LENGTH, HEX_BASE, max, value);
  }
  return parse_decimal(text, max, value);
}
