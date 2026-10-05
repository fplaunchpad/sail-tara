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
    parser_.require_subcommand(1, 1);
    ConfigureRun();
    ConfigurePlay();
    disasm_subcommand_ =
        parser_.add_subcommand("disasm", "Disassemble every 16-bit instruction word");
    RejectRepeatedOptions();
  }

  [[nodiscard]] Command Parse(std::span<const char *const> arguments) {
    try {
      // CLI11's argc is an int; main supplies a span of exactly that many arguments.
      parser_.parse(static_cast<int>(arguments.size()), arguments.data());
    } catch (const CLI::CallForHelp &) {
      return {.subcommand = Subcommand::kHelp,
              .run_options = {},
              .play_options = {},
              .help_text = parser_.help()};
    } catch (const CLI::ParseError &error) {
      throw std::runtime_error(error.what());
    }
    if (*run_subcommand_) {
      if (key_script_option_->count() != 0) {
        run_options_.key_script_path = key_script_path_;
      }
      return {.subcommand = Subcommand::kRun,
              .run_options = run_options_,
              .play_options = {},
              .help_text = {}};
    }
    if (*play_subcommand_) {
      return {.subcommand = Subcommand::kPlay,
              .run_options = {},
              .play_options = play_options_,
              .help_text = {}};
    }
    return {
        .subcommand = Subcommand::kDisasm, .run_options = {}, .play_options = {}, .help_text = {}};
  }

private:
  void ConfigureRun() {
    run_subcommand_ = parser_.add_subcommand("run", "Run an image and print the final state");
    run_subcommand_->add_option("IMAGE", run_options_.image_path, ".bin bytes or .hex words")
        ->required();
    run_subcommand_->add_flag("-t,--trace", run_options_.should_print_trace,
                              "Print each instruction's trace");
    run_subcommand_->add_option_function<std::string>(
        "-n,--max-steps",
        [this](const std::string &text) { run_options_.max_steps = ParseCount(text); },
        "Retirement limit (default 1000000; 0: unlimited)");
    run_subcommand_->add_option_function<std::string>(
        "--keys", [this](const std::string &text) { run_options_.initial_keys = ParseKeys(text); },
        "Input lines 0-31, decimal or 0x hex");
    key_script_option_ =
        run_subcommand_->add_option("--key-script", key_script_path_, "STEP KEYS lines");
    run_subcommand_->add_flag("--framebuffer", run_options_.should_print_framebuffer,
                              "Print the framebuffer");
  }

  void ConfigurePlay() {
    play_subcommand_ =
        parser_.add_subcommand("play", "Arrows/WASD steer; Q drives QUIT; Esc exits");
    play_subcommand_->add_option("IMAGE", play_options_.image_path, ".bin bytes or .hex words")
        ->required();
    play_subcommand_->add_option_function<std::string>(
        "-n,--max-steps",
        [this](const std::string &text) { play_options_.max_steps = ParseCount(text); },
        "Retirement limit (default 0: unlimited)");
    play_subcommand_->add_option_function<std::string>(
        "--hz",
        [this](const std::string &text) {
          play_options_.instructions_per_second = ParseCount(text);
        },
        "Instructions per second (default 2000; 0: as fast as possible)");
  }

  void RejectRepeatedOptions() {
    for (auto *subcommand : {run_subcommand_, play_subcommand_, disasm_subcommand_}) {
      for (auto *option : subcommand->get_options()) {
        option->multi_option_policy(CLI::MultiOptionPolicy::Throw);
        option->disable_flag_override();
      }
    }
  }

  CLI::App parser_{"TARA emulator executing Sail-generated SystemVerilog", "tara-verilator"};
  RunOptions run_options_;
  PlayOptions play_options_;
  std::string key_script_path_;
  CLI::App *run_subcommand_{};
  CLI::App *play_subcommand_{};
  CLI::App *disasm_subcommand_{};
  CLI::Option *key_script_option_{};
};

} // namespace

Command ParseCommand(std::span<const char *const> arguments) {
  return CommandLine{}.Parse(arguments);
}

} // namespace tara::verilator
