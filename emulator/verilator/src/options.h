#ifndef TARA_VERILATOR_OPTIONS_H
#define TARA_VERILATOR_OPTIONS_H

#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <string>

namespace tara::verilator {

enum class Subcommand : std::uint8_t { kRun, kPlay, kDisasm, kHelp };
inline constexpr std::uint64_t kDefaultStepLimit = 1'000'000;
inline constexpr std::uint64_t kDefaultInstructionsPerSecond = 2'000;

struct RunOptions {
  std::filesystem::path image_path;
  std::optional<std::filesystem::path> key_script_path;
  std::uint64_t max_steps = kDefaultStepLimit;
  std::uint8_t initial_keys{};
  bool should_print_trace{};
  bool should_print_framebuffer{};
};

struct PlayOptions {
  std::filesystem::path image_path;
  std::uint64_t max_steps{};
  std::uint64_t instructions_per_second = kDefaultInstructionsPerSecond;
};

struct Command {
  Subcommand subcommand = Subcommand::kHelp;
  std::optional<RunOptions> run_options;
  std::optional<PlayOptions> play_options;
  std::optional<std::string> help_text;
};

[[nodiscard]] Command ParseCommand(std::span<const char *const> arguments);

} // namespace tara::verilator

#endif
