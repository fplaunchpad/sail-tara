#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <ranges>
#include <string_view>

#include "keyboard.h"
#include "terminal_codes.h"

namespace tara::verilator {
namespace {

constexpr auto kKeyHoldDuration = std::chrono::milliseconds(150);
constexpr auto kEscapeTimeout = std::chrono::milliseconds(20);
constexpr char kInterrupt = '\x03';
constexpr std::string_view kLowercaseKeys = "wsadq";
constexpr std::string_view kUppercaseKeys = "WSADQ";
constexpr std::string_view kArrowCodes = "ABDC";

std::optional<std::size_t> FindLetterKeyIndex(char byte) {
  const auto lowercase_index = kLowercaseKeys.find(byte);
  if (lowercase_index != std::string_view::npos) {
    return lowercase_index;
  }
  const auto uppercase_index = kUppercaseKeys.find(byte);
  if (uppercase_index != std::string_view::npos) {
    return uppercase_index;
  }
  return std::nullopt;
}

std::optional<std::size_t> FindArrowKeyIndex(char byte) {
  const auto key_index = kArrowCodes.find(byte);
  return key_index == std::string_view::npos ? std::nullopt : std::optional(key_index);
}

} // namespace

void KeyboardInput::PressKey(std::optional<std::size_t> key_index, TimePoint now) {
  if (key_index) {
    key_release_times_[*key_index] = now + kKeyHoldDuration;
  }
}

InputAction KeyboardInput::HandleByte(char byte, TimePoint now) {
  switch (escape_state_) {
  case EscapeState::kEscape:
    if (byte != '[' && byte != 'O') {
      return InputAction::kExit;
    }
    escape_state_ = EscapeState::kControlSequence;
    return InputAction::kContinue;
  case EscapeState::kControlSequence:
    if (byte >= '\x20' && byte <= '\x3f') {
      return InputAction::kContinue;
    }
    escape_state_ = EscapeState::kNone;
    if (byte >= '\x40' && byte <= '\x7e') {
      PressKey(FindArrowKeyIndex(byte), now);
      return InputAction::kContinue;
    }
    break;
  case EscapeState::kNone:
    break;
  }
  if (byte == kInterrupt) {
    return InputAction::kExit;
  }
  if (byte == kEscape) {
    escape_state_ = EscapeState::kEscape;
  } else {
    PressKey(FindLetterKeyIndex(byte), now);
  }
  return InputAction::kContinue;
}

InputAction KeyboardInput::HandleBytes(std::string_view bytes, TimePoint now) {
  if (HasEscapeTimedOut(now)) {
    return InputAction::kExit;
  }
  for (const char byte : bytes) {
    const auto action = HandleByte(byte, now);
    if (escape_state_ != EscapeState::kNone) {
      escape_updated_at_ = now;
    }
    if (action == InputAction::kExit) {
      return action;
    }
  }
  return InputAction::kContinue;
}

TimePoint KeyboardInput::EscapeDeadline() const {
  return escape_state_ == EscapeState::kNone ? TimePoint::max()
                                             : escape_updated_at_ + kEscapeTimeout;
}

bool KeyboardInput::HasEscapeTimedOut(TimePoint now) const { return now >= EscapeDeadline(); }

std::uint8_t KeyboardInput::HeldKeys(TimePoint now) const {
  std::uint8_t keys{};
  for (const auto [key_index, release_time] : key_release_times_ | std::views::enumerate) {
    if (now < release_time) {
      keys |= static_cast<std::uint8_t>(std::uint8_t{1} << key_index);
    }
  }
  return keys;
}

} // namespace tara::verilator
