/* What the emulator tells the user: errors on standard error, led by the program name. */
#ifndef TARA_REPORT_H
#define TARA_REPORT_H

#include <stdbool.h>

#define PROGRAM_NAME "tara-c"

/* Print the message on standard error. Returns false, so that a function that fails can
 * `return report_error(...)`. */
bool report_error(const char *format, ...) __attribute__((format(printf, 1, 2)));

/* As report_error, followed by ": " and the text of the error number `error` (from errno). */
bool report_system_error(int error, const char *format, ...) __attribute__((format(printf, 2, 3)));

/* Flush standard output. If that, or an earlier write to it, failed, report it and return false. */
bool flush_output(void);

#endif
