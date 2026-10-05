#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <print>
#include <span>
#include <stdexcept>
#include <utility>

#include "machine.h"
#include "options.h"
#include "play.h"
#include "run.h"

namespace tara::verilator {
namespace {

auto Execute(const Command &command) -> std::uint8_t {
  if (command.help) {
    std::print("{}", *command.help);
    return 0;
  }
  Machine machine;
  switch (command.subcommand) {
  case Subcommand::kRun:
    if (command.run) {
      return RunBatch(machine, *command.run);
    }
    break;
  case Subcommand::kPlay:
    if (command.play) {
      return Play(machine, *command.play);
    }
    break;
  case Subcommand::kDisasm:
    DisassembleAll(machine);
    return 0;
  case Subcommand::kHelp:
    std::unreachable();
  }
  std::unreachable();
}

} // namespace
} // namespace tara::verilator

auto main(int argc, char *argv[]) -> int {
  try {
    const auto arguments = std::span(argv, static_cast<std::size_t>(argc));
    const auto command = tara::verilator::ParseCommand(arguments);
    const auto status = tara::verilator::Execute(command);
    if (std::fflush(stdout) != 0) {
      throw std::runtime_error("cannot write standard output");
    }
    return status;
  } catch (const std::exception &error) {
    try {
      std::println(stderr, "tara-verilator: {}", error.what());
    } catch (...) {
      // There is no further output path if reporting the error also fails.
      return 1;
    }
    return 1;
  }
}
