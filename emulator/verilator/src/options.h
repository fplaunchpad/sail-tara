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
inline constexpr std::uint64_t kDefaultFrequency = 2'000;

struct RunOptions {
  std::filesystem::path image;
  std::optional<std::filesystem::path> key_script;
  std::uint64_t max_steps = kDefaultStepLimit;
  std::uint8_t keys{};
  bool needs_trace{};
  bool needs_framebuffer{};
};

struct PlayOptions {
  std::filesystem::path image;
  std::uint64_t max_steps{};
  std::uint64_t frequency = kDefaultFrequency;
};

struct Command {
  Subcommand subcommand = Subcommand::kHelp;
  std::optional<RunOptions> run;
  std::optional<PlayOptions> play;
  std::optional<std::string> help;
};

[[nodiscard]] Command ParseCommand(std::span<const char *const> arguments);

} // namespace tara::verilator

#endif
