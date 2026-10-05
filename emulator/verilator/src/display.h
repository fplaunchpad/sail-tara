#ifndef TARA_VERILATOR_DISPLAY_H
#define TARA_VERILATOR_DISPLAY_H

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>

#include "machine.h"
#include "run.h"

namespace tara::verilator {

inline constexpr std::size_t kDisplayRows = kScreenSize / 2;

// One terminal cell holds an upper foreground pixel and a lower background pixel.
struct Cell {
  bool is_upper_set{};
  bool is_lower_set{};
  bool operator==(const Cell &) const = default;
};

class Display {
public:
  void Reset();
  [[nodiscard]] std::string Draw(const Machine &machine, const Run &run, std::uint8_t keys);

private:
  void PaintChanges(std::string &frame, const Machine &machine);
  static void PaintRow(std::string &frame, std::size_t row_index, std::span<const Cell> pixel_cells,
                       std::optional<Cell> &active_colors);

  std::array<std::array<std::optional<Cell>, kScreenSize>, kDisplayRows> rendered_rows_{};
  bool needs_clear_ = true;
};

} // namespace tara::verilator

#endif
