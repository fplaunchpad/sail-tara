#ifndef TARA_VERILATOR_TERMINAL_CODES_H
#define TARA_VERILATOR_TERMINAL_CODES_H

#include <algorithm>
#include <array>
#include <cstddef>
#include <span>
#include <string_view>

namespace tara::verilator {

inline constexpr char kEscape = '\x1b';
inline constexpr std::array kCsiBytes{kEscape, '['};
inline constexpr std::string_view kCsi{kCsiBytes};

// String literals supply the size at compile time; this boundary does not own a C array.
// NOLINTNEXTLINE(cppcoreguidelines-avoid-c-arrays,modernize-avoid-c-arrays)
template <std::size_t Size> consteval auto ControlSequence(const char (&suffix)[Size]) {
  std::array<char, Size + 1> bytes{};
  const auto suffix_begin = std::ranges::copy(kCsiBytes, bytes.begin()).out;
  std::ranges::copy(std::span(suffix).first(Size - 1), suffix_begin);
  return bytes;
}

inline constexpr auto kResetAttributes = ControlSequence("0m");

template <std::size_t... Sizes>
consteval auto JoinSequences(const std::array<char, Sizes> &...sequences) {
  std::array<char, (Sizes + ...)> bytes{};
  auto destination = bytes.begin();
  ((destination = std::ranges::copy(sequences, destination).out), ...);
  return bytes;
}

} // namespace tara::verilator

#endif
