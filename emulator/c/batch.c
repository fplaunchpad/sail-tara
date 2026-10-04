#include "batch.h"

#include <inttypes.h>
#include <stdio.h>

#include "image.h"
#include "keyscript.h"
#include "machine.h"
#include "report.h"
#include "run.h"

#define SET_PIXEL '#'
#define CLEAR_PIXEL '.'

/* Step the machine to the end of the run, with the input lines the key script gives. */
static void run_to_end(struct run *run, struct key_script *script, bool trace) {
  while (run->state == RUN_RUNNING) {
    uint8_t keys = key_script_keys(script, run->retired);
    enum step_result result = run_step(run, keys);
    if (trace && result != STEP_STOPPED)
      machine_print_trace(stdout);
  }
}

/* One line per row of pixels, the top row (y = 63) first and x = 0 at the left. */
static void print_framebuffer(FILE *out) {
  for (unsigned y = SCREEN_SIZE; y-- > 0;) {
    fputs("fb ", out);
    for (unsigned x = 0; x < SCREEN_SIZE; ++x)
      fputc(machine_pixel(x, y) ? SET_PIXEL : CLEAR_PIXEL, out);
    fputc('\n', out);
  }
}

static void print_result(const struct run *run, bool framebuffer) {
  printf("status %s\nsteps %" PRIu64 "\n", run_state_name(run->state), run->retired);
  machine_print_dump(stdout);
  if (framebuffer)
    print_framebuffer(stdout);
}

/* Load the key script, if any, and the image: everything that can fail before the run. */
static bool load_inputs(const struct options *options, struct key_script *script) {
  key_script_init(script, options->keys);
  return (!options->key_script || key_script_load(script, options->key_script)) &&
         image_load(options->image);
}

int batch_run(const struct options *options) {
  struct key_script script;
  if (!load_inputs(options, &script)) {
    key_script_free(&script);
    return EXIT_ERROR;
  }

  struct run run;
  run_start(&run, options->max_steps);
  run_to_end(&run, &script, options->trace);
  print_result(&run, options->framebuffer);
  key_script_free(&script);
  return report_flush() ? (int)run_exit_status(run.state) : EXIT_ERROR;
}
