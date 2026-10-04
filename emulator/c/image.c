#include "image.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "machine.h"

#define MEMORY_BYTES 2048
#define HEX_DIGITS "0123456789abcdefABCDEF"
#define BLANKS " \t\r\n"

static bool has_suffix(const char *text, const char *suffix) {
  size_t n = strlen(text), m = strlen(suffix);
  return n >= m && strcmp(text + n - m, suffix) == 0;
}

/* Parse a word of 1 to 4 hex digits. */
static bool parse_word(const char *token, uint16_t *word) {
  size_t digits = strspn(token, HEX_DIGITS);
  if (digits == 0 || digits > 4 || token[digits] != '\0')
    return false;
  *word = (uint16_t)strtoul(token, NULL, 16);
  return true;
}

/* Write a byte at *address and advance it; false when memory is full. */
static bool place_byte(uint16_t *address, uint8_t value) {
  if (*address == MEMORY_BYTES)
    return false;
  machine_poke((*address)++, value);
  return true;
}

static bool load_bin(FILE *image) {
  uint16_t address = 0;
  for (int c; (c = fgetc(image)) != EOF;) {
    if (!place_byte(&address, (uint8_t)c))
      return false;
  }
  return true;
}

static bool load_hex(FILE *image) {
  uint16_t address = 0;
  char line[1024];
  while (fgets(line, sizeof line, image)) {
    line[strcspn(line, ";")] = '\0';
    for (char *token = strtok(line, BLANKS); token; token = strtok(NULL, BLANKS)) {
      uint16_t word;
      if (!parse_word(token, &word))
        return false;
      if (!place_byte(&address, word >> 8) || !place_byte(&address, word & 0xFF))
        return false;
    }
  }
  return true;
}

bool image_load(const char *path) {
  bool hex = has_suffix(path, ".hex");
  if (!hex && !has_suffix(path, ".bin")) {
    fprintf(stderr, "tara-c: %s: expected a .bin or .hex image\n", path);
    return false;
  }

  FILE *image = fopen(path, "rb");
  if (!image) {
    fprintf(stderr, "tara-c: %s: %s\n", path, strerror(errno));
    return false;
  }

  bool loaded = hex ? load_hex(image) : load_bin(image);
  fclose(image);
  if (!loaded)
    fprintf(stderr, "tara-c: %s: malformed, or larger than %d bytes\n", path, MEMORY_BYTES);
  return loaded;
}
