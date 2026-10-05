#ifndef TARA_VERILATOR_INPUT_H
#define TARA_VERILATOR_INPUT_H

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>

namespace tara::verilator {

using Clock = std::chrono::steady_clock;
using Time = Clock::time_point;
inline constexpr std::size_t kInputLines = 5;

class Input {
public:
  [[nodiscard]] bool WantsQuit(std::string_view bytes, Time now);
  [[nodiscard]] bool HasExpiredEscape(Time now) const;
  [[nodiscard]] Time Deadline() const;
  [[nodiscard]] std::uint8_t HeldKeys(Time now) const;

private:
  enum class Sequence : std::uint8_t { kGround, kEscape, kControl };
  bool Feed(char byte, Time now);
  void Press(std::optional<std::size_t> line, Time now);

  Sequence sequence_ = Sequence::kGround;
  std::array<Time, kInputLines> release_deadlines_{};
  Time pending_since_;
};

} // namespace tara::verilator

#endif
