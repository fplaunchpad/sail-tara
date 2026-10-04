/* The terminal in interactive mode: raw input on the alternate screen, put back whichever way the
 * emulator ends. */
#ifndef TARA_TERMINAL_H
#define TARA_TERMINAL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

/* Whether standard input and standard output are both terminals. */
bool terminal_attached(void);

/* Switch standard input to raw mode (no echo, no line editing, and no signals from keys: Ctrl-C
 * is the byte 0x03), and the terminal to the alternate screen with a hidden cursor.
 *
 * Whichever way the emulator then ends, the terminal is put back: by close_terminal, by exit(),
 * and by the signals that end a process (SIGHUP, SIGINT, SIGQUIT, SIGTERM, and those of a crash),
 * after which the signal ends the process as it would have. On failure, print why to stderr,
 * leave the terminal as it was and return false. */
bool open_terminal(void);

/* Restore the terminal's settings, show the cursor and leave the alternate screen. Does nothing
 * if the terminal is not open. Preserves errno, and may be called from a signal handler. */
void close_terminal(void);

/* Whether the window was resized since the last call; what the screen shows may be damaged. */
bool terminal_resized(void);

/* Write to the terminal, waiting until it has taken everything; false, with errno set, if it
 * cannot. */
bool write_terminal(const char *data, size_t length);

/* Wait up to timeout_ms for input, and read what is there into buffer. Returns the number of
 * bytes read, 0 if there were none in time, or -1 if the terminal is gone. */
ssize_t read_terminal(uint8_t *buffer, size_t size, int timeout_ms);

#endif
