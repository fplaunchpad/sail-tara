#include <cstdint>
#include <cstdio>
#include <exception>
#include <print>
#include <stdexcept>
#include <utility>

#include "machine.h"
#include "options.h"
#include "play.h"
#include "run.h"

namespace tara::verilator {
namespace {

std::uint8_t Execute(const Command &command) {
  if (command.help) {
    std::print("{}", *command.help);
    return 0;
  }
  Machine machine;
  switch (command.subcommand) {
  case Subcommand::kRun:
    return RunBatch(machine, command.run.value());
  case Subcommand::kPlay:
    return Play(machine, command.play.value());
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

int main(int argc, char *argv[]) {
  try {
    const auto command = tara::verilator::ParseCommand(argc, argv);
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
