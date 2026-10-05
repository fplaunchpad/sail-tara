#include <algorithm>
#include <chrono>
#include <cstdint>
#include <limits>
#include <ranges>

#include "display.h"
#include "input.h"
#include "inputs.h"
#include "machine.h"
#include "options.h"
#include "play.h"
#include "run.h"
#include "terminal.h"

namespace tara::verilator {
namespace {

constexpr std::uint64_t kFrameRate = 60;
constexpr auto kFrameTime = std::chrono::nanoseconds(1'000'000'000 / kFrameRate);
constexpr std::uint64_t kDeadlineInterval = 64;

class FrameBudget {
public:
  explicit FrameBudget(std::uint64_t frequency) : frequency_(frequency) {}

  [[nodiscard]] std::uint64_t Next() {
    if (frequency_ == 0) {
      return std::numeric_limits<std::uint64_t>::max();
    }
    remainder_ += frequency_ % kFrameRate;
    const auto instructions = (frequency_ / kFrameRate) + (remainder_ / kFrameRate);
    remainder_ %= kFrameRate;
    return instructions;
  }

private:
  std::uint64_t frequency_;
  std::uint64_t remainder_{};
};

void AdvanceFrame(Run &run, std::uint8_t keys, std::uint64_t budget, Time deadline) {
  for (const auto instruction : std::views::iota(std::uint64_t{0}, budget)) {
    if (run.Status() != RunStatus::kRunning) {
      break;
    }
    run.Step(keys);
    if (instruction % kDeadlineInterval == 0 && Clock::now() >= deadline) {
      break;
    }
  }
}

bool WaitForInput(const Terminal &terminal, Input &input, Time deadline) {
  while (Clock::now() < deadline) {
    const auto bytes = terminal.Read(std::min(deadline, input.Deadline()));
    const auto now = Clock::now();
    if (input.WantsQuit(bytes, now) || input.HasExpiredEscape(now)) {
      return true;
    }
  }
  return false;
}

} // namespace

std::uint8_t Play(Machine &machine, const PlayOptions &options) {
  // Validate the image before entering the alternate screen.
  machine.Load(ReadImage(options.image));
  const Terminal terminal;
  Input input;
  Display display;
  FrameBudget budget(options.frequency);
  Run run(machine, options.max_steps);

  auto start = Clock::now();
  for (;;) {
    const auto end = start + kFrameTime;
    const auto keys = input.HeldKeys(Clock::now());
    if (terminal.WasResized()) {
      display.Reset();
    }
    AdvanceFrame(run, keys, budget.Next(), end);
    terminal.Write(display.Draw(machine, run, keys));
    if (WaitForInput(terminal, input, end)) {
      return run.ExitStatus();
    }
    const auto now = Clock::now();
    start = now > end + kFrameTime ? now : end;
  }
}

} // namespace tara::verilator
