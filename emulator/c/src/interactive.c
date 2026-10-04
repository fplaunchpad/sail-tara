#include "interactive.h"

#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "clock.h"
#include "display.h"
#include "image.h"
#include "input.h"
#include "keys.h"
#include "machine.h"
#include "options.h"
#include "report.h"
#include "run.h"
#include "terminal.h"

#define FRAME_RATE 30
#define FRAME_NS (NS_PER_SECOND / FRAME_RATE)
/* Instructions between two looks at the clock. */
#define CHUNK 256
#define STATUS_MAX 128
/* The most bytes of input taken from the terminal at once. */
#define READ_SIZE 1024

struct player {
  struct run run;
  struct input input;
  struct display display;
  uint64_t hz;   /* instructions per second; 0: as many as fit in a frame */
  uint64_t owed; /* the fraction of an instruction the frames so far owe, in 1/FRAME_RATE */
};

/* Why the wait for input ended: the time was up, the player quit, or the terminal is gone. */
enum wait_result { WAIT_ELAPSED, WAIT_QUIT, WAIT_LOST };

/* Why the play ended: the player quit, or the terminal failed. */
enum play_end { PLAY_QUIT, PLAY_WRITE_FAILED, PLAY_TERMINAL_LOST };

static void init_player(struct player *player, const struct play_options *options) {
  start_run(&player->run, options->max_steps);
  init_input(&player->input);
  reset_display(&player->display);
  player->hz = options->hz;
  player->owed = 0;
}

/* The number of instructions for the next frame: hz / FRAME_RATE, with the remainder carried
 * from frame to frame so that the rate comes out at hz. */
static uint64_t frame_budget(struct player *player) {
  if (player->hz == 0) {
    return UINT64_MAX;
  }

  player->owed += player->hz % FRAME_RATE;
  uint64_t budget = (player->hz / FRAME_RATE) + (player->owed / FRAME_RATE);
  player->owed %= FRAME_RATE;
  return budget;
}

/* Run the frame's instructions with the input lines `keys`. A frame also ends at its deadline, so
 * that a rate beyond what the host can do slows the run and not the screen. Returns whether any
 * instruction retired: only then can the framebuffer have changed. */
static bool run_frame(struct player *player, uint8_t keys, int64_t deadline) {
  uint64_t retired = player->run.retired;
  uint64_t budget = frame_budget(player);
  for (uint64_t steps = 1; steps <= budget && player->run.state == RUN_RUNNING; ++steps) {
    step_run(&player->run, keys);
    if (steps % CHUNK == 0 && clock_ns() >= deadline) {
      break;
    }
  }
  return player->run.retired != retired;
}

static void format_status(char status[STATUS_MAX], const struct run *run, uint8_t keys) {
  char spelling[KEY_LINES + 1];
  spell_keys(keys, spelling);
  snprintf(status, STATUS_MAX, "%s  pc 0x%04x  steps %" PRIu64 "  keys %s",
           run_state_name(run->state), machine_pc(), run->retired, spelling);
}

/* Paint the screen. False, with errno set, if the terminal does not take it. */
static bool draw(struct player *player, uint8_t keys, bool changed) {
  char status[STATUS_MAX];
  format_status(status, &player->run, keys);

  char *frame = NULL;
  size_t size = 0;
  FILE *out = open_memstream(&frame, &size);
  if (!out) {
    return false;
  }

  draw_display(&player->display, out, status, changed);
  bool drawn = false;
  if (fclose(out) == 0) {
    drawn = write_terminal(frame, size);
  }
  free(frame);
  return drawn;
}

/* The milliseconds from `now` until `time`, rounded up: a poll that lasts that long is not over
 * early. */
static int timeout_ms(int64_t now, int64_t time) {
  return now < time ? (int)((time - now + NS_PER_MS - 1) / NS_PER_MS) : 0;
}

/* Take in what the player types until the deadline, and what is already waiting after it. */
static enum wait_result wait_for_input(struct input *input, int64_t deadline) {
  for (;;) {
    /* Wake in time to see whether an ESC stands alone. */
    int64_t escape = input_deadline(input);
    int64_t wake = escape < deadline ? escape : deadline;

    uint8_t bytes[READ_SIZE];
    ssize_t count = read_terminal(bytes, sizeof bytes, timeout_ms(clock_ns(), wake));
    int64_t now = clock_ns();
    if (count < 0) {
      return WAIT_LOST;
    }
    if (count > 0 && feed_input(input, now, bytes, (size_t)count)) {
      return WAIT_QUIT;
    }
    if (expire_input(input, now)) {
      return WAIT_QUIT;
    }
    if (now >= deadline && (size_t)count < sizeof bytes) {
      return WAIT_ELAPSED;
    }
  }
}

/* Where the frame after one that was to end at `end` starts: there, unless the frames have fallen
 * more than a frame behind, which they do not catch up. */
static int64_t next_frame_start(int64_t end) {
  int64_t now = clock_ns();
  return now > end + FRAME_NS ? now : end;
}

/* Play until the player quits or the terminal fails; errno says why a write failed. */
static enum play_end play(struct player *player) {
  int64_t start = clock_ns();
  for (;;) {
    int64_t end = start + FRAME_NS;
    uint8_t keys = held_keys(&player->input, clock_ns());
    if (terminal_resized()) {
      reset_display(&player->display);
    }

    bool retired = run_frame(player, keys, end);
    if (!draw(player, keys, retired)) {
      return PLAY_WRITE_FAILED;
    }

    switch (wait_for_input(&player->input, end)) {
    case WAIT_ELAPSED:
      break;
    case WAIT_QUIT:
      return PLAY_QUIT;
    case WAIT_LOST:
      return PLAY_TERMINAL_LOST;
    }
    start = next_frame_start(end);
  }
}

int run_interactive(const struct play_options *options) {
  if (!terminal_attached()) {
    report_error("play needs a terminal on standard input and output");
    return EXIT_ERROR;
  }
  if (!load_program(options->image) || !open_terminal()) {
    return EXIT_ERROR;
  }

  struct player player;
  init_player(&player, options);
  enum play_end end = play(&player);
  int error = errno;
  close_terminal();

  switch (end) {
  case PLAY_QUIT:
    return run_exit_status(player.run.state);
  case PLAY_WRITE_FAILED:
    report_system_error(error, "cannot draw on the terminal");
    break;
  case PLAY_TERMINAL_LOST:
    report_error("the terminal is gone");
    break;
  }
  return EXIT_ERROR;
}
