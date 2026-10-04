#include "clock.h"

#include <stdint.h>
#include <time.h>

int64_t clock_ns(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return ((int64_t)now.tv_sec * NS_PER_SECOND) + now.tv_nsec;
}
