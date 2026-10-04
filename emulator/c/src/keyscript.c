#include "keyscript.h"

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "keys.h"
#include "number.h"
#include "report.h"

#define BLANKS " \t\n\v\f\r"
#define MAX_WORDS 3
#define FIRST_CAPACITY 16

void key_script_init(struct key_script *script, uint8_t initial) {
  *script = (struct key_script){.keys = initial};
}

void key_script_free(struct key_script *script) {
  free(script->changes);
  script->changes = NULL;
  script->count = script->capacity = 0;
}

static bool append(struct key_script *script, struct key_change change) {
  if (script->count == script->capacity) {
    size_t capacity = script->capacity ? 2 * script->capacity : FIRST_CAPACITY;
    struct key_change *changes = realloc(script->changes, capacity * sizeof *changes);
    if (!changes) {
      return report_error("out of memory");
    }
    script->changes = changes;
    script->capacity = capacity;
  }
  script->changes[script->count++] = change;
  return true;
}

/* Split a line, up to its comment, into at most MAX_WORDS words; returns how many it has. */
static size_t split_words(char *line, char *words[MAX_WORDS]) {
  char *comment = strchr(line, ';');
  if (comment) {
    *comment = '\0';
  }

  size_t count = 0;
  char *rest;
  for (char *word = strtok_r(line, BLANKS, &rest); word && count < MAX_WORDS;
       word = strtok_r(NULL, BLANKS, &rest)) {
    words[count++] = word;
  }
  return count;
}

/* Add the change a line spells; a line without words adds none. Reports a line that is not
 * STEP KEYS, or whose step does not follow the one before it. */
static bool add_line(struct key_script *script, char *line, const char *path, unsigned number) {
  char *words[MAX_WORDS];
  size_t count = split_words(line, words);
  if (count == 0) {
    return true;
  }
  if (count != 2) {
    return report_error("%s:%u: expected STEP KEYS", path, number);
  }

  struct key_change change;
  if (!parse_decimal(words[0], UINT64_MAX, &change.step)) {
    return report_error("%s:%u: '%s' is not a step (a decimal count of retirements)", path, number,
                        words[0]);
  }
  if (!keys_parse(words[1], &change.keys)) {
    return report_error("%s:%u: '%s' is not input lines (0-%u, decimal or 0x hex)", path, number,
                        words[1], KEYS_MAX);
  }

  if (script->count && change.step <= script->changes[script->count - 1].step) {
    return report_error("%s:%u: step %" PRIu64 " does not follow step %" PRIu64, path, number,
                        change.step, script->changes[script->count - 1].step);
  }
  return append(script, change);
}

/* Add the changes of every line of the file. */
static bool read_lines(struct key_script *script, FILE *file, const char *path) {
  char *line = NULL;
  size_t size = 0;
  bool valid = true;
  ssize_t length;
  for (unsigned number = 1; valid && (length = getline(&line, &size, file)) != -1; ++number) {
    if (strlen(line) != (size_t)length) {
      valid = report_error("%s:%u: contains a NUL byte", path, number);
    } else {
      valid = add_line(script, line, path, number);
    }
  }
  free(line);
  if (valid && ferror(file)) {
    return report_system_error(errno, "%s", path);
  }
  return valid;
}

bool key_script_load(struct key_script *script, const char *path) {
  FILE *file = fopen(path, "r");
  if (!file) {
    return report_system_error(errno, "%s", path);
  }

  bool loaded = read_lines(script, file, path);
  fclose(file);
  return loaded;
}

uint8_t key_script_keys(struct key_script *script, uint64_t retired) {
  while (script->next < script->count && script->changes[script->next].step <= retired) {
    script->keys = script->changes[script->next++].keys;
  }
  return script->keys;
}
