#ifndef TARA_VERILATOR_INPUTS_H
#define TARA_VERILATOR_INPUTS_H

#include <cstdint>
#include <filesystem>
#include <string_view>
#include <vector>

namespace tara::verilator {

[[nodiscard]] std::uint64_t ParseCount(std::string_view text);
[[nodiscard]] std::uint8_t ParseKeys(std::string_view text);
[[nodiscard]] std::vector<std::uint8_t> ReadImage(const std::filesystem::path &path);

struct KeyChange {
  std::uint64_t step;
  std::uint8_t keys;
};

class KeySchedule {
public:
  explicit KeySchedule(std::uint8_t initial) : initial_(initial) {}

  void Load(const std::filesystem::path &path);
  [[nodiscard]] std::uint8_t At(std::uint64_t step) const;

private:
  std::uint8_t initial_;
  std::vector<KeyChange> changes_;
};

} // namespace tara::verilator

#endif
