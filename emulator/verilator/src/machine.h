#ifndef TARA_VERILATOR_MACHINE_H
#define TARA_VERILATOR_MACHINE_H

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <string>

namespace tara::verilator {

inline constexpr std::size_t kRegisterCount = 8;
inline constexpr std::size_t kMemoryBytes = 2'048;
inline constexpr std::size_t kScreenSize = 64;
inline constexpr std::uint8_t kAllKeys = 31;

enum class StepResult : std::uint8_t { kRetired, kStopped, kIllegal };

struct State {
  std::array<std::uint16_t, kRegisterCount> registers{};
  std::array<std::uint8_t, kMemoryBytes> memory{};
  std::uint16_t program_counter{};
  std::uint16_t next_program_counter{};
  std::uint16_t trace_address{};
  std::uint16_t trace_word{};
  std::uint8_t keys{};
  bool is_halted{};

  auto operator==(const State &) const -> bool = default;
};

// Sail's C helpers own process-wide state, so only one Machine may be alive at a time.
class Machine {
public:
  Machine();
  ~Machine();
  Machine(const Machine &) = delete;
  auto operator=(const Machine &) -> Machine & = delete;
  Machine(Machine &&) = delete;
  auto operator=(Machine &&) -> Machine & = delete;

  void Load(std::span<const std::uint8_t> image);
  [[nodiscard]] auto Step(std::uint8_t keys) -> StepResult;
  [[nodiscard]] auto ReadState() const -> State;
  void WriteState(const State &state);

  [[nodiscard]] auto ProgramCounter() const -> std::uint16_t;
  [[nodiscard]] auto IsHalted() const -> bool;
  [[nodiscard]] auto IsPixelSet(std::size_t pixel_x, std::size_t pixel_y) const -> bool;
  [[nodiscard]] auto Trace() const -> std::string;
  [[nodiscard]] auto Dump() const -> std::string;
  [[nodiscard]] auto Disassemble(std::uint16_t word) const -> std::string;

private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace tara::verilator

#endif
