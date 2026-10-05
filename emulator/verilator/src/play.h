#ifndef TARA_VERILATOR_PLAY_H
#define TARA_VERILATOR_PLAY_H

#include <cstdint>

#include "machine.h"
#include "options.h"

namespace tara::verilator {

[[nodiscard]] auto Play(Machine &machine, const PlayOptions &options) -> std::uint8_t;

} // namespace tara::verilator

#endif
