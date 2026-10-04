#include "display.h"

#include <string.h>

#define STATUS_ROW (DISPLAY_ROWS + 1)

/* A cell holds two pixels: the upper one is the foreground, the lower one the background. */
#define CELL_UPPER 1
#define CELL_LOWER 2
#define CELL_UNKNOWN 0xFF

/* SGR parameters of 24-bit colors: set pixels amber, clear pixels dark gray. */
#define SET_FOREGROUND "38;2;255;176;0"
#define SET_BACKGROUND "48;2;255;176;0"
#define CLEAR_FOREGROUND "38;2;28;28;28"
#define CLEAR_BACKGROUND "48;2;28;28;28"

/* The colors of each kind of cell. */
static const char *const CELL_COLORS[] = {
    [0] = CLEAR_FOREGROUND ";" CLEAR_BACKGROUND,
    [CELL_UPPER] = SET_FOREGROUND ";" CLEAR_BACKGROUND,
    [CELL_LOWER] = CLEAR_FOREGROUND ";" SET_BACKGROUND,
    [CELL_UPPER | CELL_LOWER] = SET_FOREGROUND ";" SET_BACKGROUND,
};

/* U+2580 UPPER HALF BLOCK in UTF-8. */
#define UPPER_HALF_BLOCK "\xe2\x96\x80"

#define RESET_ATTRIBUTES "\x1b[0m"
#define CLEAR_SCREEN "\x1b[2J"

void display_reset(struct display *display) {
  memset(display->cells, CELL_UNKNOWN, sizeof display->cells);
  display->clear = true;
}

/* The cells of a row of text, read from the framebuffer. */
static void read_row(unsigned row, uint8_t cells[DISPLAY_COLUMNS]) {
  unsigned upper = SCREEN_SIZE - 1 - (2 * row);
  for (unsigned x = 0; x < DISPLAY_COLUMNS; ++x) {
    cells[x] = (uint8_t)((machine_pixel(x, upper) ? CELL_UPPER : 0) |
                         (machine_pixel(x, upper - 1) ? CELL_LOWER : 0));
  }
}

/* The first and last column in which two rows differ; false if they do not. */
static bool changed_columns(const uint8_t *shown, const uint8_t *cells, unsigned *first,
                            unsigned *last) {
  unsigned begin = 0;
  while (begin < DISPLAY_COLUMNS && shown[begin] == cells[begin])
    ++begin;
  if (begin == DISPLAY_COLUMNS)
    return false;

  unsigned end = DISPLAY_COLUMNS - 1;
  while (shown[end] == cells[end])
    --end;
  *first = begin;
  *last = end;
  return true;
}

/* Paint the cells of a row from column `first` to `last`. The colors change only where the cells
 * do: `color` is the cell colors in effect, or CELL_UNKNOWN. */
static void paint(FILE *out, unsigned row, const uint8_t *cells, unsigned first, unsigned last,
                  uint8_t *color) {
  fprintf(out, "\x1b[%u;%uH", row + 1, first + 1);
  for (unsigned x = first; x <= last; ++x) {
    if (cells[x] != *color) {
      fprintf(out, "\x1b[%sm", CELL_COLORS[cells[x]]);
      *color = cells[x];
    }
    fputs(UPPER_HALF_BLOCK, out);
  }
}

/* Paint the rows of cells that differ from what the terminal shows. */
static void paint_changes(struct display *display, FILE *out) {
  uint8_t color = CELL_UNKNOWN;
  for (unsigned row = 0; row < DISPLAY_ROWS; ++row) {
    uint8_t cells[DISPLAY_COLUMNS];
    read_row(row, cells);

    unsigned first, last;
    if (changed_columns(display->cells[row], cells, &first, &last)) {
      paint(out, row, cells, first, last, &color);
      memcpy(display->cells[row], cells, sizeof cells);
    }
  }
  if (color != CELL_UNKNOWN)
    fputs(RESET_ATTRIBUTES, out);
}

void display_draw(struct display *display, FILE *out, const char *status, bool changed) {
  if (display->clear) {
    fputs(RESET_ATTRIBUTES CLEAR_SCREEN, out);
    display->clear = false;
    changed = true;
  }
  if (changed)
    paint_changes(display, out);

  fprintf(out, "\x1b[%u;1H%s\x1b[K", STATUS_ROW, status);
}
