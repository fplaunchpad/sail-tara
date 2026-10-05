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
  [[nodiscard]] auto WantsQuit(std::string_view bytes, Time now) -> bool;
  [[nodiscard]] auto HasExpiredEscape(Time now) const -> bool;
  [[nodiscard]] auto Deadline() const -> Time;
  [[nodiscard]] auto HeldKeys(Time now) const -> std::uint8_t;

private:
  enum class Sequence : std::uint8_t { kGround, kEscape, kControl };
  auto Feed(char byte, Time now) -> bool;
  void Press(std::optional<std::size_t> line, Time now);

  Sequence sequence_ = Sequence::kGround;
  std::array<Time, kInputLines> release_deadlines_{};
  Time pending_since_;
};

} // namespace tara::verilator

#endif
