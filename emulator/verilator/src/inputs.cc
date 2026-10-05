#include <algorithm>
#include <array>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <format>
#include <fstream>
#include <ios>
#include <iterator>
#include <limits>
#include <memory>
#include <optional>
#include <ranges>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

#include "inputs.h"
#include "machine.h"

namespace tara::verilator {
namespace {

// std::from_chars takes a plain int for its numeric base.
constexpr int kDecimalBase = 10;
constexpr int kHexBase = 16;
constexpr std::size_t kMaxFileBytes = 1'048'576;
constexpr std::size_t kChunkBytes = 4'096;
constexpr std::size_t kMaxHexWordDigits = 4;
constexpr std::uint16_t kBitsPerByte = 8;

std::uint64_t ParseNumber(std::string_view text, int base, std::uint64_t maximum) {
  std::uint64_t value{};
  const char *const digits_begin = std::to_address(text.begin());
  const char *const digits_end = std::to_address(text.end());
  const auto [parsed_end, parse_error] = std::from_chars(digits_begin, digits_end, value, base);
  if (parse_error != std::errc{} || parsed_end != digits_end || value > maximum) {
    throw std::runtime_error(std::format("invalid number '{}'", text));
  }
  return value;
}

std::string ReadFile(const std::filesystem::path &path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    throw std::runtime_error(std::format("cannot open {}", path.string()));
  }
  std::string contents;
  std::array<char, kChunkBytes> chunk{};
  while (file.read(chunk.data(), static_cast<std::streamsize>(chunk.size())) || file.gcount() > 0) {
    contents.append(chunk.data(), static_cast<std::size_t>(file.gcount()));
    if (contents.size() > kMaxFileBytes) {
      throw std::runtime_error(std::format("{}: file is too large", path.string()));
    }
  }
  if (!file.eof()) {
    throw std::runtime_error(std::format("cannot read {}", path.string()));
  }
  return contents;
}

std::string_view WithoutComment(std::string_view line) { return line.substr(0, line.find(';')); }

std::vector<std::uint8_t> ReadHex(std::string_view text) {
  std::istringstream lines{std::string(text)};
  std::vector<std::uint8_t> image;
  for (std::string line; std::getline(lines, line);) {
    std::istringstream words{std::string(WithoutComment(line))};
    for (std::string spelling; words >> spelling;) {
      if (spelling.size() > kMaxHexWordDigits) {
        throw std::runtime_error("hex words must contain one to four digits");
      }
      const auto word = ParseNumber(spelling, kHexBase, std::numeric_limits<std::uint16_t>::max());
      image.push_back(static_cast<std::uint8_t>(word >> kBitsPerByte));
      image.push_back(static_cast<std::uint8_t>(word));
      if (image.size() > kMemoryBytes) {
        throw std::runtime_error("image is larger than TARA memory");
      }
    }
  }
  return image;
}

std::optional<KeyChange> ParseKeyChange(std::string_view line) {
  std::istringstream fields{std::string(WithoutComment(line))};
  std::string step_count;
  std::string key_lines;
  std::string extra_field;
  if (!(fields >> step_count)) {
    return std::nullopt;
  }
  if (!(fields >> key_lines) || fields >> extra_field) {
    throw std::runtime_error("key script expects STEP KEYS on each line");
  }
  return KeyChange{.step = ParseCount(step_count), .keys = ParseKeys(key_lines)};
}

} // namespace

std::uint64_t ParseCount(std::string_view text) {
  return ParseNumber(text, kDecimalBase, std::numeric_limits<std::uint64_t>::max());
}

std::uint8_t ParseKeys(std::string_view text) {
  auto base = kDecimalBase;
  if (text.starts_with("0x") || text.starts_with("0X")) {
    text.remove_prefix(2);
    base = kHexBase;
  }
  return static_cast<std::uint8_t>(ParseNumber(text, base, kAllKeys));
}

std::vector<std::uint8_t> ReadImage(const std::filesystem::path &path) {
  const auto suffix = path.extension();
  if (suffix != ".bin" && suffix != ".hex") {
    throw std::runtime_error("IMAGE must have a .bin or .hex suffix");
  }
  const auto contents = ReadFile(path);
  if (suffix == ".hex") {
    return ReadHex(contents);
  }
  if (contents.size() > kMemoryBytes) {
    throw std::runtime_error("image is larger than TARA memory");
  }
  return {std::from_range, contents};
}

void KeySchedule::Load(const std::filesystem::path &path) {
  const auto contents = ReadFile(path);
  if (contents.contains('\0')) {
    throw std::runtime_error("key script contains a NUL byte");
  }
  std::istringstream lines(contents);
  for (std::string line; std::getline(lines, line);) {
    if (const auto change = ParseKeyChange(line)) {
      if (!changes_.empty() && change->step <= changes_.back().step) {
        throw std::runtime_error("key script steps must increase strictly");
      }
      changes_.push_back(*change);
    }
  }
}

std::uint8_t KeySchedule::KeysAtStep(std::uint64_t step) const {
  const auto next_change = std::ranges::upper_bound(changes_, step, {}, &KeyChange::step);
  return next_change == changes_.begin() ? initial_keys_ : std::prev(next_change)->keys;
}

} // namespace tara::verilator
