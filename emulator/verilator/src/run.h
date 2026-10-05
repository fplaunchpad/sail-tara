#ifndef TARA_VERILATOR_RUN_H
#define TARA_VERILATOR_RUN_H

#include <cstdint>
#include <format>
#include <functional>
#include <string_view>
#include <utility>

#include "machine.h"
#include "options.h"

namespace tara::verilator {

enum class RunStatus : std::uint8_t { kRunning, kHalted, kLimit, kIllegal };

class Run {
public:
  Run(Machine &machine, std::uint64_t limit) : machine_(machine), limit_(limit) {}

  auto Step(std::uint8_t keys) -> StepResult;
  [[nodiscard]] auto Status() const -> RunStatus;

  [[nodiscard]] auto Retirements() const -> std::uint64_t { return retirements_; }

  [[nodiscard]] auto ExitStatus() const -> std::uint8_t;

private:
  std::reference_wrapper<Machine> machine_;
  std::uint64_t limit_;
  std::uint64_t retirements_{};
  bool has_illegal_opcode_{};
};

[[nodiscard]] auto RunBatch(Machine &machine, const RunOptions &options) -> std::uint8_t;
void DisassembleAll(const Machine &machine);

} // namespace tara::verilator

template <> struct std::formatter<tara::verilator::RunStatus> : std::formatter<std::string_view> {
  auto format(tara::verilator::RunStatus status, std::format_context &context) const {
    using tara::verilator::RunStatus;
    std::string_view spelling;
    switch (status) {
    case RunStatus::kRunning:
      spelling = "running";
      break;
    case RunStatus::kHalted:
      spelling = "halted";
      break;
    case RunStatus::kLimit:
      spelling = "limit";
      break;
    case RunStatus::kIllegal:
      spelling = "illegal";
      break;
    default:
      std::unreachable();
    }
    return std::formatter<std::string_view>::format(spelling, context);
  }
};

#endif
