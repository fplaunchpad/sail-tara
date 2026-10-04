#include "report.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

/* Room for strerror_r's text of an error number. */
#define REASON_SIZE 256

/* Print "tara-c: MESSAGE" on standard error, followed by ": REASON" if there is a reason. */
__attribute__((format(printf, 1, 0))) static void
print_report(const char *format, va_list arguments, const char *reason) {
  fputs(PROGRAM_NAME ": ", stderr);
  vfprintf(stderr, format, arguments);
  if (reason) {
    fprintf(stderr, ": %s", reason);
  }
  fputc('\n', stderr);
}

bool report_error(const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  print_report(format, arguments, NULL);
  va_end(arguments);
  return false;
}

bool report_system_error(int error, const char *format, ...) {
  char reason[REASON_SIZE];
  if (strerror_r(error, reason, sizeof reason) != 0) {
    snprintf(reason, sizeof reason, "error %d", error);
  }

  va_list arguments;
  va_start(arguments, format);
  print_report(format, arguments, reason);
  va_end(arguments);
  return false;
}

bool flush_output(void) {
  if (fflush(stdout) != 0) {
    return report_system_error(errno, "standard output");
  }
  if (ferror(stdout)) {
    return report_error("standard output: write failed");
  }
  return true;
}
