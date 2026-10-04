#include "image.h"

#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "machine.h"
#include "number.h"
#include "report.h"

#define MEMORY_BYTES 2048
#define WORD_DIGITS 4
#define HEX_DIGIT_BITS 4
/* Files are read whole, in chunks of this many bytes, up to the largest a hex image can sensibly
 * be (2048 bytes of words, with room for comments). */
#define READ_CHUNK 4096
#define MAX_FILE_BYTES ((size_t)1024 * 1024)

enum format { FORMAT_BIN, FORMAT_HEX };

/* A file's contents, read whole. */
struct contents {
  char *data;
  size_t size;
};

/* An image being placed into memory. */
struct loader {
  const char *path;
  unsigned address; /* where the next byte goes */
};

/* A hex image being parsed: its text, how far it has been read, and the line there, from 1. */
struct cursor {
  const char *text;
  size_t size;
  size_t position;
  unsigned line;
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
  if (dot && strcmp(dot, ".bin") == 0) {
    *format = FORMAT_BIN;
  } else if (dot && strcmp(dot, ".hex") == 0) {
    *format = FORMAT_HEX;
  } else {
    return false;
  }
  return true;
}

static bool place_byte(struct loader *loader, uint8_t value) {
  if (loader->address == MEMORY_BYTES) {
    return report_error("%s: larger than the %d-byte memory", loader->path, MEMORY_BYTES);
  }
  machine_poke((uint16_t)loader->address++, value);
  return true;
}

static bool place_word(struct loader *loader, uint16_t word) {
  return place_byte(loader, (uint8_t)(word >> CHAR_BIT)) && place_byte(loader, (uint8_t)word);
}

/* Read the whole file at path into memory; on failure, report it. */
static bool read_contents(const char *path, struct contents *contents) {
  FILE *file = fopen(path, "rb");
  if (!file) {
    return report_system_error(errno, "%s", path);
  }

  struct contents read = {.data = NULL, .size = 0};
  int error = 0;
  for (size_t count = READ_CHUNK; count == READ_CHUNK && read.size <= MAX_FILE_BYTES;) {
    char *grown = realloc(read.data, read.size + READ_CHUNK);
    if (!grown) {
      error = errno;
      break;
    }
    read.data = grown;
    count = fread(read.data + read.size, 1, READ_CHUNK, file);
    read.size += count;
  }
  if (!error && ferror(file)) {
    error = errno;
  }
  fclose(file);

  if (!error && read.size > MAX_FILE_BYTES) {
    free(read.data);
    return report_error("%s: larger than %zu bytes, too large for an image", path, MAX_FILE_BYTES);
  }
  if (error) {
    free(read.data);
    return report_system_error(error, "%s", path);
  }
  *contents = read;
  return true;
}

static bool load_bin(struct loader *loader, const struct contents *contents) {
  for (size_t index = 0; index < contents->size; ++index) {
    if (!place_byte(loader, (uint8_t)contents->data[index])) {
      return false;
    }
  }
  return true;
}

/* Whitespace between the words of a hex image, whatever the locale. */
static bool is_blank(char character) {
  return character == ' ' || character == '\t' || character == '\n' || character == '\r' ||
         character == '\v' || character == '\f';
}

/* Skip whitespace and comments, counting the lines passed. */
static void skip_blanks(struct cursor *cursor) {
  while (cursor->position < cursor->size) {
    char character = cursor->text[cursor->position];
    if (character == ';') {
      while (cursor->position < cursor->size && cursor->text[cursor->position] != '\n') {
        ++cursor->position;
      }
    } else if (is_blank(character)) {
      cursor->line += character == '\n';
      ++cursor->position;
    } else {
      return;
    }
  }
}

static bool report_bad_digit(const char *path, unsigned line, unsigned char character) {
  if (character >= ' ' && character <= '~') {
    return report_error("%s:%u: '%c' is not a hex digit", path, line, character);
  }
  return report_error("%s:%u: byte 0x%02x is not a hex digit", path, line, character);
}

/* Read a word of 1 to 4 hex digits, ended by whitespace, a comment or the end of the text. */
static bool read_word(struct cursor *cursor, const char *path, uint16_t *word) {
  unsigned value = 0;
  unsigned digits = 0;
  for (; cursor->position < cursor->size; ++cursor->position) {
    char character = cursor->text[cursor->position];
    int digit = hex_digit_value((unsigned char)character);
    if (digit < 0) {
      if (character != ';' && !is_blank(character)) {
        return report_bad_digit(path, cursor->line, (unsigned char)character);
      }
      break;
    }
    if (++digits > WORD_DIGITS) {
      return report_error("%s:%u: a word has at most %d hex digits", path, cursor->line,
                          WORD_DIGITS);
    }
    value = (value << HEX_DIGIT_BITS) | (unsigned)digit;
  }
  *word = (uint16_t)value;
  return true;
}

static bool load_hex(struct loader *loader, const struct contents *contents) {
  struct cursor cursor = {.text = contents->data, .size = contents->size, .position = 0, .line = 1};
  for (skip_blanks(&cursor); cursor.position < cursor.size; skip_blanks(&cursor)) {
    uint16_t word = 0;
    if (!read_word(&cursor, loader->path, &word) || !place_word(loader, word)) {
      return false;
    }
  }
  return true;
}

bool image_load(const char *path) {
  enum format format;
  if (!format_of(path, &format)) {
    return report_error("%s: expected a .bin or .hex image", path);
  }

  struct contents contents = {.data = NULL, .size = 0};
  if (!read_contents(path, &contents)) {
    return false;
  }

  struct loader loader = {.path = path, .address = 0};
  bool loaded = false;
  if (format == FORMAT_HEX) {
    loaded = load_hex(&loader, &contents);
  } else {
    loaded = load_bin(&loader, &contents);
  }
  free(contents.data);
  return loaded;
}
