/* The five input lines of the machine: bits 0-4 of the byte at 0x5FF. */
#ifndef TARA_KEYS_H
#define TARA_KEYS_H

#include <stdbool.h>
#include <stdint.h>

/* The bit of each line in the input byte. */
enum key_line { KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_QUIT, KEY_LINES };

#define KEYS_MAX ((1u << KEY_LINES) - 1)

/* Parse a set of lines: a number from 0 to KEYS_MAX, in decimal or 0x hex. */
bool parse_keys(const char *text, uint8_t *keys);

/* Spell the lines in order, a letter for each held one and '-' for a released one: "U-L-Q". */
void spell_keys(uint8_t keys, char spelling[KEY_LINES + 1]);

#endif
