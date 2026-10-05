#include <cstddef>
#include <cstdint>
#include <limits>
#include <print>
#include <ranges>
#include <string>
#include <utility>

#include "inputs.h"
#include "machine.h"
#include "options.h"
#include "run.h"

namespace tara::verilator {
namespace {

void PrintFramebuffer(const Machine &machine) {
  for (const auto row : std::views::iota(std::size_t{0}, kScreenSize) | std::views::reverse) {
    std::string pixels(kScreenSize, '.');
    for (auto [column, pixel] : pixels | std::views::enumerate) {
      if (machine.IsPixelSet(static_cast<std::size_t>(column), row)) {
        pixel = '#';
      }
    }
    std::println("fb {}", pixels);
  }
}

} // namespace

RunStatus Run::Status() const {
  if (has_illegal_opcode_) {
    return RunStatus::kIllegal;
  }
  if (machine_.get().IsHalted()) {
    return RunStatus::kHalted;
  }
  if (limit_ != 0 && retirements_ == limit_) {
    return RunStatus::kLimit;
  }
  return RunStatus::kRunning;
}

StepResult Run::Step(std::uint8_t keys) {
  const auto result = machine_.get().Step(keys);
  if (result == StepResult::kRetired) {
    ++retirements_;
  } else if (result == StepResult::kIllegal) {
    has_illegal_opcode_ = true;
  }
  return result;
}

std::uint8_t Run::ExitStatus() const {
  constexpr std::uint8_t kLimitExit = 3;
  constexpr std::uint8_t kIllegalExit = 4;
  switch (Status()) {
  case RunStatus::kRunning:
  case RunStatus::kHalted:
    return 0;
  case RunStatus::kLimit:
    return kLimitExit;
  case RunStatus::kIllegal:
    return kIllegalExit;
  }
  std::unreachable();
}

std::uint8_t RunBatch(Machine &machine, const RunOptions &options) {
  KeySchedule keys(options.keys);
  if (options.key_script) {
    keys.Load(*options.key_script);
  }
  machine.Load(ReadImage(options.image));

  Run run(machine, options.max_steps);
  while (run.Status() == RunStatus::kRunning) {
    const auto result = run.Step(keys.At(run.Retirements()));
    if (options.needs_trace && result != StepResult::kStopped) {
      std::println("{}", machine.Trace());
    }
  }

  std::println("status {}\nsteps {}", run.Status(), run.Retirements());
  std::print("{}", machine.Dump());
  if (options.needs_framebuffer) {
    PrintFramebuffer(machine);
  }
  return run.ExitStatus();
}

void DisassembleAll(const Machine &machine) {
  constexpr auto kWordCount = std::uint32_t{std::numeric_limits<std::uint16_t>::max()} + 1;
  for (const auto word : std::views::iota(std::uint32_t{0}, kWordCount)) {
    std::println("{:04x} {}", word, machine.Disassemble(static_cast<std::uint16_t>(word)));
  }
}

} // namespace tara::verilator
