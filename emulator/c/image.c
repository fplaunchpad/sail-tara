#include "image.h"

#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "machine.h"
#include "number.h"
#include "report.h"

#define MEMORY_BYTES 2048
#define WORD_DIGITS 4

enum format { FORMAT_BIN, FORMAT_HEX };

/* An image being read into memory. */
struct loader {
  FILE *file;
  const char *path;
  unsigned address; /* where the next byte goes */
  unsigned line;    /* the line being read, from 1 */
};

/* The suffix of the file name, such as ".bin", or NULL if it has none. Like Python's
 * Path.suffix, it needs a stem before it and a character after the dot. */
static const char *suffix(const char *path) {
  const char *name = strrchr(path, '/');
  name = name ? name + 1 : path;

  const char *dot = strrchr(name, '.');
  return dot && dot != name && dot[1] ? dot : NULL;
}

static bool format_of(const char *path, enum format *format) {
  const char *dot = suffix(path);
  if (dot && strcmp(dot, ".bin") == 0)
    *format = FORMAT_BIN;
  else if (dot && strcmp(dot, ".hex") == 0)
    *format = FORMAT_HEX;
  else
    return false;
  return true;
}

static bool place_byte(struct loader *loader, uint8_t value) {
  if (loader->address == MEMORY_BYTES)
    return report_error("%s: larger than the %d-byte memory", loader->path, MEMORY_BYTES);
  machine_poke((uint16_t)loader->address++, value);
  return true;
}

static bool place_word(struct loader *loader, uint16_t word) {
  return place_byte(loader, (uint8_t)(word >> 8)) && place_byte(loader, (uint8_t)(word & 0xFF));
}

static bool load_bin(struct loader *loader) {
  for (int c; (c = fgetc(loader->file)) != EOF;) {
    if (!place_byte(loader, (uint8_t)c))
      return false;
  }
  return true;
}

/* The first character of the next word of a hex image, or EOF. Skips whitespace and comments,
 * counting the lines it passes. */
static int skip_blanks(struct loader *loader) {
  int c = fgetc(loader->file);
  while (c != EOF) {
    if (c == ';') {
      do
        c = fgetc(loader->file);
      while (c != EOF && c != '\n');
      continue;
    }
    if (c == '\n')
      ++loader->line;
    else if (!isspace(c))
      break;
    c = fgetc(loader->file);
  }
  return c;
}

static bool report_bad_digit(const struct loader *loader, int c) {
  if (isprint(c))
    return report_error("%s:%u: '%c' is not a hex digit", loader->path, loader->line, c);
  return report_error("%s:%u: byte 0x%02x is not a hex digit", loader->path, loader->line, c);
}

enum token { TOKEN_WORD, TOKEN_END, TOKEN_BAD };

/* Read the next word of a hex image: 1 to 4 hex digits ended by whitespace, a comment or the end
 * of the file. Reports a malformed word. */
static enum token next_word(struct loader *loader, uint16_t *word) {
  int c = skip_blanks(loader);
  if (c == EOF)
    return TOKEN_END;

  unsigned value = 0, digits = 0;
  for (; hex_digit_value(c) >= 0; c = fgetc(loader->file)) {
    if (++digits > WORD_DIGITS) {
      report_error("%s:%u: a word has at most %d hex digits", loader->path, loader->line,
                   WORD_DIGITS);
      return TOKEN_BAD;
    }
    value = (value << 4) | (unsigned)hex_digit_value(c);
  }
  if (c != EOF && c != ';' && !isspace(c)) {
    report_bad_digit(loader, c);
    return TOKEN_BAD;
  }

  ungetc(c, loader->file); /* the delimiter is for skip_blanks; EOF is not pushed back */
  *word = (uint16_t)value;
  return TOKEN_WORD;
}

static bool load_hex(struct loader *loader) {
  uint16_t word;
  enum token token;
  while ((token = next_word(loader, &word)) == TOKEN_WORD) {
    if (!place_word(loader, word))
      return false;
  }
  return token == TOKEN_END;
}

bool image_load(const char *path) {
  enum format format;
  if (!format_of(path, &format))
    return report_error("%s: expected a .bin or .hex image", path);

  FILE *file = fopen(path, "rb");
  if (!file)
    return report_error("%s: %s", path, strerror(errno));

  struct loader loader = {.file = file, .path = path, .line = 1};
  bool loaded = format == FORMAT_HEX ? load_hex(&loader) : load_bin(&loader);
  if (loaded && ferror(file))
    loaded = report_error("%s: %s", path, strerror(errno));
  fclose(file);
  return loaded;
}
