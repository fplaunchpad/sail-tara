/* Key scripts: the input lines over a run. Each line of a script file is "STEP KEYS": from the
 * instruction executed after STEP retirements on, the input lines are KEYS (as --keys takes them).
 * Steps are decimal and strictly increase; ';' starts a comment; blank lines are allowed. */
#ifndef TARA_KEYSCRIPT_H
#define TARA_KEYSCRIPT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct key_change {
  uint64_t step;
  uint8_t keys;
};

/* The changes of a script, played back in step order. */
struct key_script {
  struct key_change *changes;
  size_t count, capacity;
  size_t next;  /* the first change not played yet */
  uint8_t keys; /* the input lines now */
};

/* Start an empty script, in which the input lines are `initial` throughout. */
void key_script_init(struct key_script *script, uint8_t initial);
void key_script_free(struct key_script *script);

/* Add the changes of the script file at path; on failure, print why to stderr and return false. */
bool key_script_load(struct key_script *script, const char *path);

/* The input lines for the instruction executed after `retired` retirements: those of the last
 * change with a step of at most `retired`, else the initial ones. The counts asked for must not
 * decrease. */
uint8_t key_script_keys(struct key_script *script, uint64_t retired);

#endif
