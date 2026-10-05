#include <algorithm>
#include <chrono>
#include <cstdint>
#include <limits>
#include <ranges>

#include "display.h"
#include "inputs.h"
#include "keyboard.h"
#include "machine.h"
#include "options.h"
#include "play.h"
#include "run.h"
#include "terminal.h"

namespace tara::verilator {
namespace {

constexpr std::uint64_t kFramesPerSecond = 60;
constexpr auto kFrameDuration = std::chrono::nanoseconds(1'000'000'000 / kFramesPerSecond);
constexpr std::uint64_t kInstructionsPerClockCheck = 64;

class FrameBudget {
public:
  explicit FrameBudget(std::uint64_t instructions_per_second)
      : instructions_per_second_(instructions_per_second) {}

  [[nodiscard]] std::uint64_t NextInstructionCount() {
    if (instructions_per_second_ == 0) {
      return std::numeric_limits<std::uint64_t>::max();
    }
    instruction_remainder_ += instructions_per_second_ % kFramesPerSecond;
    const auto instruction_count =
        (instructions_per_second_ / kFramesPerSecond) + (instruction_remainder_ / kFramesPerSecond);
    instruction_remainder_ %= kFramesPerSecond;
    return instruction_count;
  }

private:
  std::uint64_t instructions_per_second_;
  std::uint64_t instruction_remainder_{};
};

void AdvanceFrame(Run &run, std::uint8_t keys, std::uint64_t instruction_budget,
                  TimePoint frame_deadline) {
  for (const auto instruction_index : std::views::iota(std::uint64_t{0}, instruction_budget)) {
    if (run.Status() != RunStatus::kRunning) {
      break;
    }
    run.Step(keys);
    if (instruction_index % kInstructionsPerClockCheck == 0 && Clock::now() >= frame_deadline) {
      break;
    }
  }
}

InputAction HandleFrameInput(const Terminal &terminal, KeyboardInput &keyboard,
                             TimePoint frame_deadline) {
  // A full CPU frame still needs one nonblocking poll to keep controls responsive.
  for (;;) {
    const auto bytes = terminal.Read(std::min(frame_deadline, keyboard.EscapeDeadline()));
    const auto now = Clock::now();
    if (keyboard.HandleBytes(bytes, now) == InputAction::kExit) {
      return InputAction::kExit;
    }
    if (Clock::now() >= frame_deadline) {
      return InputAction::kContinue;
    }
  }
}

} // namespace

std::uint8_t Play(Machine &machine, const PlayOptions &options) {
  // Validate the image before entering the alternate screen.
  machine.LoadImage(ReadImage(options.image_path));
  Terminal terminal;
  KeyboardInput keyboard;
  Display display;
  FrameBudget frame_budget(options.instructions_per_second);
  Run run(machine, options.max_steps);

  auto frame_start = Clock::now();
  for (;;) {
    const auto frame_deadline = frame_start + kFrameDuration;
    const auto keys = keyboard.HeldKeys(Clock::now());
    if (terminal.ConsumeResize()) {
      display.Reset();
    }
    AdvanceFrame(run, keys, frame_budget.NextInstructionCount(), frame_deadline);
    terminal.Write(display.Draw(machine, run, keys));
    if (HandleFrameInput(terminal, keyboard, frame_deadline) == InputAction::kExit) {
      return run.ExitStatus();
    }
    const auto now = Clock::now();
    frame_start = now > frame_deadline + kFrameDuration ? now : frame_deadline;
  }
}

} // namespace tara::verilator
