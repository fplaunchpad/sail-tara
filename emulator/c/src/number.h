/* Strict parsing of numbers given on the command line, in key scripts and in hex images: the
 * whole text must be digits (no sign, no spaces, no octal) and the value in range. */
#ifndef TARA_NUMBER_H
#define TARA_NUMBER_H

#include <stdbool.h>
#include <stdint.h>

/* The value of a hex digit in either case, or -1 if the character is not one. */
int hex_digit_value(int character);

/* Parse decimal digits; false if text is anything else or the value exceeds max. */
bool parse_decimal(const char *text, uint64_t max, uint64_t *value);

/* As parse_decimal, but "0x" or "0X" and hex digits are accepted too. A leading 0 does not make
 * the number octal. */
bool parse_decimal_or_hex(const char *text, uint64_t max, uint64_t *value);

#endif
