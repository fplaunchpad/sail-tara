#include "disasm.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

#include "machine.h"
#include "report.h"
#include "run.h"

int disasm_run(void) {
  for (uint32_t word = 0; word <= UINT16_MAX; ++word) {
    printf("%04" PRIx32 " ", word);
    machine_print_disasm(stdout, (uint16_t)word);
    putchar('\n');
  }
  if (!report_flush()) {
    return EXIT_ERROR;
  }
  return EXIT_HALTED;
}
