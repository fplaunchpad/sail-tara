#ifndef TARA_VERILATOR_KEYBOARD_H
#define TARA_VERILATOR_KEYBOARD_H

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>

namespace tara::verilator {

using Clock = std::chrono::steady_clock;
using TimePoint = Clock::time_point;
inline constexpr std::size_t kInputLines = 5;

enum class InputAction : std::uint8_t { kContinue, kExit };

class KeyboardInput {
public:
  [[nodiscard]] InputAction HandleBytes(std::string_view bytes, TimePoint now);
  [[nodiscard]] bool HasEscapeTimedOut(TimePoint now) const;
  [[nodiscard]] TimePoint EscapeDeadline() const;
  [[nodiscard]] std::uint8_t HeldKeys(TimePoint now) const;

private:
  enum class EscapeState : std::uint8_t { kNone, kEscape, kControlSequence };
  InputAction HandleByte(char byte, TimePoint now);
  void PressKey(std::optional<std::size_t> key_index, TimePoint now);

  EscapeState escape_state_ = EscapeState::kNone;
  std::array<TimePoint, kInputLines> key_release_times_{};
  TimePoint escape_updated_at_;
};

} // namespace tara::verilator

#endif
