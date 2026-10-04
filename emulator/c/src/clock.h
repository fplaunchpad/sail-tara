/* Time, in nanoseconds on a monotonic clock. */
#ifndef TARA_CLOCK_H
#define TARA_CLOCK_H

#include <stdint.h>

#define NS_PER_MS INT64_C(1000000)
#define NS_PER_SECOND INT64_C(1000000000)

/* The time now. Only differences between two times mean anything. */
int64_t clock_ns(void);

#endif
