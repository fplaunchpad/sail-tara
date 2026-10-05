#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <format>
#include <iterator>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>

#include "display.h"
#include "machine.h"
#include "run.h"

namespace tara::verilator {
namespace {

constexpr std::string_view kKeyLetters = "UDLRQ";
constexpr std::string_view kAmber = "255;176;0";
constexpr std::string_view kDark = "28;28;28";

std::string_view PixelColor(bool is_set) { return is_set ? kAmber : kDark; }

std::array<Cell, kScreenSize> ReadRow(const Machine &machine, std::size_t row_index) {
  const auto upper_pixel_y = kScreenSize - 1 - 2 * row_index;
  std::array<Cell, kScreenSize> pixel_cells{};
  for (auto [column_index, cell] : pixel_cells | std::views::enumerate) {
    const auto pixel_x = static_cast<std::size_t>(column_index);
    cell = {.is_upper_set = machine.IsPixelSet(pixel_x, upper_pixel_y),
            .is_lower_set = machine.IsPixelSet(pixel_x, upper_pixel_y - 1)};
  }
  return pixel_cells;
}

void SetColors(std::string &frame, const Cell &cell) {
  std::format_to(std::back_inserter(frame), "\x1b[38;2;{};48;2;{}m",
                 PixelColor(cell.is_upper_set), PixelColor(cell.is_lower_set));
}

std::string HeldLetters(std::uint8_t keys) {
  std::string held(kKeyLetters);
  for (auto [line, letter] : held | std::views::enumerate) {
    if ((keys & (std::uint8_t{1} << line)) == 0) {
      letter = '-';
    }
  }
  return held;
}

void AppendStatus(std::string &frame, const Machine &machine, const Run &run, std::uint8_t keys) {
  std::format_to(std::back_inserter(frame),
                 "\x1b[0m\x1b[{};1H{}  pc 0x{:04x}  steps {}  keys {}\x1b[K", kDisplayRows + 1,
                 run.Status(), machine.ProgramCounter(), run.Retirements(), HeldLetters(keys));
}

} // namespace

void Display::Reset() {
  for (auto &rendered_cells : rendered_rows_) {
    rendered_cells.fill(std::nullopt);
  }
  needs_clear_ = true;
}

void Display::PaintRow(std::string &frame, std::size_t row_index, std::span<const Cell> pixel_cells,
                       std::optional<Cell> &active_colors) {
  std::format_to(std::back_inserter(frame), "\x1b[{};1H", row_index + 1);
  for (const auto &cell : pixel_cells) {
    if (active_colors != cell) {
      SetColors(frame, cell);
      active_colors = cell;
    }
    frame += "▀";
  }
}

void Display::PaintChanges(std::string &frame, const Machine &machine) {
  std::optional<Cell> active_colors;
  for (auto [row_index, rendered_cells] : rendered_rows_ | std::views::enumerate) {
    const auto display_row = static_cast<std::size_t>(row_index);
    const auto pixel_cells = ReadRow(machine, display_row);
    if (!std::ranges::equal(rendered_cells, pixel_cells)) {
      PaintRow(frame, display_row, pixel_cells, active_colors);
      std::ranges::copy(pixel_cells, rendered_cells.begin());
    }
  }
}

std::string Display::Draw(const Machine &machine, const Run &run, std::uint8_t keys) {
  std::string frame;
  if (needs_clear_) {
    frame += "\x1b[0m\x1b[2J";
    needs_clear_ = false;
  }
  PaintChanges(frame, machine);
  AppendStatus(frame, machine, run, keys);
  return frame;
}

} // namespace tara::verilator
