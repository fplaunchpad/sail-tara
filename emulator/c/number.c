#include "number.h"

#include <string.h>

int hex_digit_value(int c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

/* Parse one or more digits of the given base, rejecting a value that exceeds max before it
 * overflows. */
static bool parse_digits(const char *text, unsigned base, uint64_t max, uint64_t *value) {
  if (*text == '\0')
    return false;

  uint64_t result = 0;
  for (; *text; ++text) {
    int digit = hex_digit_value((unsigned char)*text);
    if (digit < 0 || (unsigned)digit >= base)
      return false;
    if ((uint64_t)digit > max || result > (max - (uint64_t)digit) / base)
      return false;
    result = (result * base) + (uint64_t)digit;
  }
  *value = result;
  return true;
}

bool parse_decimal(const char *text, uint64_t max, uint64_t *value) {
  return parse_digits(text, 10, max, value);
}

bool parse_decimal_or_hex(const char *text, uint64_t max, uint64_t *value) {
  if (strncmp(text, "0x", 2) == 0 || strncmp(text, "0X", 2) == 0)
    return parse_digits(text + 2, 16, max, value);
  return parse_decimal(text, max, value);
}
