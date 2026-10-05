#include <span>
#include <stdexcept>
#include <string>

#include <CLI/CLI.hpp>

#include "inputs.h"
#include "options.h"

namespace tara::verilator {
namespace {

class CommandLine {
public:
  CommandLine() {
    app_.require_subcommand(1, 1);
    ConfigureRun();
    ConfigurePlay();
    disasm_command_ = app_.add_subcommand("disasm", "Disassemble every 16-bit instruction word");
    RejectRepeatedOptions();
  }

  [[nodiscard]] Command Parse(std::span<const char *const> arguments) {
    try {
      // CLI11's argc is an int; main supplies a span of exactly that many arguments.
      app_.parse(static_cast<int>(arguments.size()), arguments.data());
    } catch (const CLI::CallForHelp &) {
      return {.subcommand = Subcommand::kHelp, .run = {}, .play = {}, .help = app_.help()};
    } catch (const CLI::ParseError &error) {
      throw std::runtime_error(error.what());
    }
    if (*run_command_) {
      if (script_option_->count() != 0) {
        run_options_.key_script = script_path_;
      }
      return {.subcommand = Subcommand::kRun, .run = run_options_, .play = {}, .help = {}};
    }
    if (*play_command_) {
      return {.subcommand = Subcommand::kPlay, .run = {}, .play = play_options_, .help = {}};
    }
    return {.subcommand = Subcommand::kDisasm, .run = {}, .play = {}, .help = {}};
  }

private:
  void ConfigureRun() {
    run_command_ = app_.add_subcommand("run", "Run an image and print the final state");
    run_command_->add_option("IMAGE", run_options_.image, ".bin bytes or .hex words")->required();
    run_command_->add_flag("-t,--trace", run_options_.needs_trace,
                           "Print each instruction's trace");
    run_command_->add_option_function<std::string>(
        "-n,--max-steps",
        [this](const std::string &text) { run_options_.max_steps = ParseCount(text); },
        "Retirement limit (default 1000000; 0: unlimited)");
    run_command_->add_option_function<std::string>(
        "--keys", [this](const std::string &text) { run_options_.keys = ParseKeys(text); },
        "Input lines 0-31, decimal or 0x hex");
    script_option_ = run_command_->add_option("--key-script", script_path_, "STEP KEYS lines");
    run_command_->add_flag("--framebuffer", run_options_.needs_framebuffer,
                           "Print the framebuffer");
  }

  void ConfigurePlay() {
    play_command_ = app_.add_subcommand("play", "Arrows/WASD steer; Q drives QUIT; Esc exits");
    play_command_->add_option("IMAGE", play_options_.image, ".bin bytes or .hex words")->required();
    play_command_->add_option_function<std::string>(
        "-n,--max-steps",
        [this](const std::string &text) { play_options_.max_steps = ParseCount(text); },
        "Retirement limit (default 0: unlimited)");
    play_command_->add_option_function<std::string>(
        "--hz", [this](const std::string &text) { play_options_.frequency = ParseCount(text); },
        "Instructions per second (default 2000; 0: as fast as possible)");
  }

  void RejectRepeatedOptions() {
    for (auto *subcommand : {run_command_, play_command_, disasm_command_}) {
      for (auto *option : subcommand->get_options()) {
        option->multi_option_policy(CLI::MultiOptionPolicy::Throw);
        option->disable_flag_override();
      }
    }
  }

  CLI::App app_{"TARA emulator executing Sail-generated SystemVerilog", "tara-verilator"};
  RunOptions run_options_;
  PlayOptions play_options_;
  std::string script_path_;
  CLI::App *run_command_{};
  CLI::App *play_command_{};
  CLI::App *disasm_command_{};
  CLI::Option *script_option_{};
};

} // namespace

Command ParseCommand(std::span<const char *const> arguments) {
  return CommandLine{}.Parse(arguments);
}

} // namespace tara::verilator
