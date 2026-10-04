#include "batch.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

#include "image.h"
#include "keyscript.h"
#include "machine.h"
#include "options.h"
#include "report.h"
#include "run.h"

#define SET_PIXEL '#'
#define CLEAR_PIXEL '.'

/* Step the machine to the end of the run, with the input lines the key script gives. */
static void run_to_end(struct run *run, struct key_script *script, bool trace) {
  while (run->state == RUN_RUNNING) {
    uint8_t keys = scripted_keys(script, run->retired);
    enum step_result result = step_run(run, keys);
    if (trace && result != STEP_STOPPED) {
      print_trace(stdout);
    }
  }
}

/* One line per row of pixels, the top row (y = 63) first and x = 0 at the left. */
static void print_framebuffer(FILE *out) {
  for (unsigned y = SCREEN_SIZE; y-- > 0;) {
    fputs("fb ", out);
    for (unsigned x = 0; x < SCREEN_SIZE; ++x) {
      fputc(machine_pixel(x, y) ? SET_PIXEL : CLEAR_PIXEL, out);
    }
    fputc('\n', out);
  }
}

static void print_result(const struct run *run, bool framebuffer) {
  printf("status %s\nsteps %" PRIu64 "\n", run_state_name(run->state), run->retired);
  print_dump(stdout);
  if (framebuffer) {
    print_framebuffer(stdout);
  }
}

/* Load the key script, if any, and the image: everything that can fail before the run. */
static bool load_inputs(const struct options *options, struct key_script *script) {
  init_key_script(script, options->keys);
  return (!options->key_script || load_key_script(script, options->key_script)) &&
         load_program(options->image);
}

int run_batch(const struct options *options) {
  struct key_script script;
  if (!load_inputs(options, &script)) {
    free_key_script(&script);
    return EXIT_ERROR;
  }

  struct run run;
  start_run(&run, options->max_steps);
  run_to_end(&run, &script, options->trace);
  print_result(&run, options->framebuffer);
  free_key_script(&script);
  if (!flush_output()) {
    return EXIT_ERROR;
  }
  return (int)run_exit_status(run.state);
}
