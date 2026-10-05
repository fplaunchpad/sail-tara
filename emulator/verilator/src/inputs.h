#ifndef TARA_VERILATOR_INPUTS_H
#define TARA_VERILATOR_INPUTS_H

#include <cstdint>
#include <filesystem>
#include <string_view>
#include <vector>

namespace tara::verilator {

[[nodiscard]] auto ParseCount(std::string_view text) -> std::uint64_t;
[[nodiscard]] auto ParseKeys(std::string_view text) -> std::uint8_t;
[[nodiscard]] auto ReadImage(const std::filesystem::path &path) -> std::vector<std::uint8_t>;

struct KeyChange {
  std::uint64_t step;
  std::uint8_t keys;
};

class KeySchedule {
public:
  explicit KeySchedule(std::uint8_t initial) : initial_(initial) {}

  void Load(const std::filesystem::path &path);
  [[nodiscard]] auto At(std::uint64_t step) const -> std::uint8_t;

private:
  std::uint8_t initial_;
  std::vector<KeyChange> changes_;
};

} // namespace tara::verilator

#endif
