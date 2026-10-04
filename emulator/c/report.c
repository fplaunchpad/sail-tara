#include "report.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

bool report_error(const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  fputs(PROGRAM_NAME ": ", stderr);
  vfprintf(stderr, format, arguments);
  fputc('\n', stderr);
  va_end(arguments);
  return false;
}

bool report_flush(void) {
  if (fflush(stdout) != 0)
    return report_error("standard output: %s", strerror(errno));
  if (ferror(stdout))
    return report_error("standard output: write failed");
  return true;
}
