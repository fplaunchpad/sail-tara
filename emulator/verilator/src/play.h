#ifndef TARA_VERILATOR_PLAY_H
#define TARA_VERILATOR_PLAY_H

#include <cstdint>

#include "machine.h"
#include "options.h"

namespace tara::verilator {

[[nodiscard]] std::uint8_t Play(Machine &machine, const PlayOptions &options);

} // namespace tara::verilator

#endif
