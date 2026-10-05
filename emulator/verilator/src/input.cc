#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <ranges>
#include <string_view>

#include "input.h"
#include "terminal_codes.h"

namespace tara::verilator {
namespace {

constexpr auto kHoldTime = std::chrono::milliseconds(150);
constexpr auto kEscapeTime = std::chrono::milliseconds(20);
constexpr char kInterrupt = '\x03';
constexpr std::string_view kLetters = "wsadq";
constexpr std::string_view kUpperLetters = "WSADQ";
constexpr std::string_view kArrows = "ABDC";

auto LetterLine(char byte) -> std::optional<std::size_t> {
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

auto ArrowLine(char byte) -> std::optional<std::size_t> {
  const auto line = kArrows.find(byte);
  return line == std::string_view::npos ? std::nullopt : std::optional(line);
}

} // namespace

void Input::Press(std::optional<std::size_t> line, Time now) {
  if (line) {
    release_deadlines_[*line] = now + kHoldTime;
  }
}

auto Input::Feed(char byte, Time now) -> bool {
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

auto Input::WantsQuit(std::string_view bytes, Time now) -> bool {
  const bool wants_quit =
      std::ranges::any_of(bytes, [this, now](char byte) -> bool { return Feed(byte, now); });
  if (!bytes.empty() && sequence_ != Sequence::kGround) {
    pending_since_ = now;
  }
  return wants_quit;
}

auto Input::Deadline() const -> Time {
  return sequence_ == Sequence::kGround ? Time::max() : pending_since_ + kEscapeTime;
}

auto Input::HasExpiredEscape(Time now) const -> bool { return now >= Deadline(); }

auto Input::HeldKeys(Time now) const -> std::uint8_t {
  std::uint8_t keys{};
  for (const auto [line, release_deadline] : release_deadlines_ | std::views::enumerate) {
    if (now < release_deadline) {
      keys |= static_cast<std::uint8_t>(std::uint8_t{1} << line);
    }
  }
  return keys;
}

} // namespace tara::verilator
