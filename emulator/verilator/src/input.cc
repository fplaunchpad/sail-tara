#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <ranges>
#include <string_view>

#include "input.h"

namespace tara::verilator {
namespace {

constexpr auto kHoldTime = std::chrono::milliseconds(150);
constexpr auto kEscapeTime = std::chrono::milliseconds(20);
constexpr char kEscape = '\x1b';
constexpr char kInterrupt = '\x03';
constexpr std::string_view kLetters = "wsadq";
constexpr std::string_view kUpperLetters = "WSADQ";
constexpr std::string_view kArrows = "ABDC";

std::optional<std::size_t> LetterLine(char byte) {
  const auto lower = kLetters.find(byte);
  if (lower != std::string_view::npos) {
    return lower;
  }
  const auto upper = kUpperLetters.find(byte);
  if (upper != std::string_view::npos) {
    return upper;
  }
  return std::nullopt;
}

std::optional<std::size_t> ArrowLine(char byte) {
  const auto line = kArrows.find(byte);
  return line == std::string_view::npos ? std::nullopt : std::optional(line);
}

} // namespace

void Input::Press(std::optional<std::size_t> line, Time now) {
  if (line) {
    release_deadlines_[*line] = now + kHoldTime;
  }
}

bool Input::Feed(char byte, Time now) {
  switch (sequence_) {
  case Sequence::kEscape:
    if (byte != '[' && byte != 'O') {
      return true;
    }
    sequence_ = Sequence::kControl;
    return false;
  case Sequence::kControl:
    if (byte >= '\x20' && byte <= '\x3f') {
      return false;
    }
    sequence_ = Sequence::kGround;
    if (byte >= '\x40' && byte <= '\x7e') {
      Press(ArrowLine(byte), now);
      return false;
    }
    break;
  case Sequence::kGround:
    break;
  }
  if (byte == kInterrupt) {
    return true;
  }
  if (byte == kEscape) {
    sequence_ = Sequence::kEscape;
  } else {
    Press(LetterLine(byte), now);
  }
  return false;
}

bool Input::WantsQuit(std::string_view bytes, Time now) {
  const bool wants_quit =
      std::ranges::any_of(bytes, [this, now](char byte) { return Feed(byte, now); });
  if (!bytes.empty() && sequence_ != Sequence::kGround) {
    pending_since_ = now;
  }
  return wants_quit;
}

Time Input::Deadline() const {
  return sequence_ == Sequence::kGround ? Time::max() : pending_since_ + kEscapeTime;
}

bool Input::HasExpiredEscape(Time now) const { return now >= Deadline(); }

std::uint8_t Input::HeldKeys(Time now) const {
  std::uint8_t keys{};
  for (const auto [line, release_deadline] : release_deadlines_ | std::views::enumerate) {
    if (now < release_deadline) {
      keys |= static_cast<std::uint8_t>(std::uint8_t{1} << line);
    }
  }
  return keys;
}

} // namespace tara::verilator
