#include <chrono>
#include <exception>
#include <print>
#include <stdexcept>
#include <string>
#include <string_view>

#include "keyboard.h"
#include "terminal_codes.h"

namespace tara::verilator {
namespace {

void Require(bool is_satisfied, std::string_view message) {
  if (!is_satisfied) {
    throw std::runtime_error(std::string(message));
  }
}

void CheckExpiredEscape() {
  KeyboardInput keyboard;
  const TimePoint start{};
  Require(keyboard.HandleBytes(std::string_view(&kEscape, 1), start) == InputAction::kContinue,
          "Escape must wait for a possible control sequence");
  const auto escape_deadline = keyboard.EscapeDeadline();

  Require(keyboard.HandleBytes({}, escape_deadline - std::chrono::milliseconds(1)) ==
              InputAction::kContinue,
          "empty input before the deadline must keep waiting");
  Require(keyboard.EscapeDeadline() == escape_deadline,
          "empty input must preserve the Escape deadline");

  Require(keyboard.HandleBytes("[A", escape_deadline) == InputAction::kExit,
          "late arrow bytes must not cancel an expired Escape");
  Require(keyboard.HeldKeys(escape_deadline) == 0, "expired Escape must not press a key");
}

void CheckFragmentedArrow() {
  KeyboardInput keyboard;
  const TimePoint start{};
  const auto arrow_received = start + std::chrono::milliseconds(10);
  Require(keyboard.HandleBytes(std::string_view(&kEscape, 1), start) == InputAction::kContinue,
          "Escape must begin the arrow sequence");
  Require(keyboard.HandleBytes("[", start + std::chrono::milliseconds(5)) == InputAction::kContinue,
          "an on-time sequence prefix must keep waiting");
  Require(keyboard.HandleBytes("A", arrow_received) == InputAction::kContinue,
          "an on-time arrow must continue play");

  Require(keyboard.HeldKeys(arrow_received) == 1, "up arrow must hold only UP");
  Require(!keyboard.HasEscapeTimedOut(arrow_received + std::chrono::milliseconds(20)),
          "a completed arrow must clear the Escape deadline");
  Require(keyboard.HeldKeys(arrow_received + std::chrono::milliseconds(149)) == 1,
          "UP must remain held before its release time");
  Require(keyboard.HeldKeys(arrow_received + std::chrono::milliseconds(150)) == 0,
          "UP must release at its deadline");
}

} // namespace
} // namespace tara::verilator

int main() {
  try {
    tara::verilator::CheckExpiredEscape();
    tara::verilator::CheckFragmentedArrow();
  } catch (const std::exception &error) {
    try {
      std::println(stderr, "{}", error.what());
    } catch (...) {
      return 1;
    }
    return 1;
  }
}
