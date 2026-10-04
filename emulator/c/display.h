/* The framebuffer and the status line on the terminal screen.
 *
 * The 64x64 pixels are 32 rows by 64 columns of U+2580 (upper half block). In the cell at row r
 * and column x, the foreground color shows pixel (x, 63 - 2r) and the background pixel
 * (x, 62 - 2r); a set pixel is amber (#FFB000), a clear one dark gray (#1C1C1C). The status line
 * is on the row below. Positions are absolute, so a frame never depends on where the cursor is. */
#ifndef TARA_DISPLAY_H
#define TARA_DISPLAY_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "machine.h"

enum { DISPLAY_ROWS = SCREEN_SIZE / 2, DISPLAY_COLUMNS = SCREEN_SIZE };

/* What the terminal shows, so that a frame paints only what changed. */
struct display {
  bool clear; /* the screen is to be cleared first */
  uint8_t cells[DISPLAY_ROWS][DISPLAY_COLUMNS];
};

/* Forget what the terminal shows: the next frame clears the screen and paints everything. */
void display_reset(struct display *display);

/* Write to out the escape sequences that paint the framebuffer where it differs from what the
 * display knows, and then rewrite the status line, whole, with `status` (plain text). Reading the
 * framebuffer is the costly part: pass changed = false if it cannot have changed since the last
 * call. After a reset it is read anyway. */
void display_draw(struct display *display, FILE *out, const char *status, bool changed);

#endif
