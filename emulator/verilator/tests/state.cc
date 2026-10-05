#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <print>
#include <ranges>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>

#include "inputs.h"
#include "machine.h"

namespace tara::verilator {
namespace {

constexpr std::uint16_t kProgramAddress = 0x04'00;
constexpr std::uint16_t kLastByteStorePc = kProgramAddress + 2;
constexpr std::uint16_t kHaltPc = kProgramAddress + 6;
constexpr std::uint64_t kStepsBeforeIllegalOpcode = 3;
constexpr std::uint16_t kIllegalInstructionPc = 6;
constexpr std::uint16_t kPcAfterIllegalInstruction = 8;

State SeedState(std::span<const std::uint8_t> program) {
  constexpr std::size_t kMemoryStride = 37;
  constexpr std::size_t kMemorySeed = 0x5b;

  State state{
      .registers = {0, 0x13'57, 0x24'68, 0x36'9c, 0x48'ad, 0x5a'be, 0x6b'cf, 0x7d'e1},
      .memory = {},
      .program_counter = kProgramAddress,
      .next_program_counter = 0xde'ad,
      .trace_address = 0x12'34,
      .trace_word = 0xab'cd,
      .keys = 0x1b,
      .is_halted = false,
  };
  for (auto [address, byte] : state.memory | std::views::enumerate) {
    byte = static_cast<std::uint8_t>((static_cast<std::size_t>(address) * kMemoryStride) +
                                     kMemorySeed);
  }
  std::ranges::copy(program, std::span(state.memory).subspan(kProgramAddress).begin());
  return state;
}

void Require(bool is_satisfied, std::string_view message) {
  if (!is_satisfied) {
    throw std::runtime_error(std::string(message));
  }
}

void CheckNoop(const State &seed) {
  Machine machine;
  machine.WriteState(seed);
  auto expected = seed;
  expected.program_counter = kLastByteStorePc;
  expected.next_program_counter = kLastByteStorePc;
  expected.trace_address = kProgramAddress;
  expected.trace_word = 0;
  expected.keys = 1;

  const auto result = machine.Step(1);
  const auto actual = machine.ReadState();

  Require(result == StepResult::kRetired, "NOP must retire");
  Require(actual == expected,
          "NOP must preserve every register and RAM byte and update fetch state");
}

void CheckBoundaryStores(State seed) {
  seed.program_counter = kLastByteStorePc;
  Machine machine;
  machine.WriteState(seed);
  auto expected_memory = seed.memory;
  expected_memory.back() = static_cast<std::uint8_t>(seed.registers[1]);
  expected_memory.front() = static_cast<std::uint8_t>(seed.registers[2]);

  const auto last_byte_result = machine.Step(2);
  const auto state_after_last_byte_store = machine.ReadState();
  const auto first_byte_result = machine.Step(3);
  const auto state_after_first_byte_store = machine.ReadState();

  Require(last_byte_result == StepResult::kRetired, "last-byte store must retire");
  Require(first_byte_result == StepResult::kRetired, "first-byte store must retire");
  Require(state_after_last_byte_store.memory.back() == expected_memory.back(),
          "store must reach the last RAM byte");
  Require(state_after_first_byte_store.memory == expected_memory,
          "stores must change only the two boundary bytes");
  Require(state_after_first_byte_store.registers == seed.registers,
          "stores must preserve every register");
  Require(state_after_first_byte_store.program_counter == kHaltPc, "stores must advance the PC");
}

void CheckHaltedPreservation(State seed) {
  seed.program_counter = kHaltPc;
  Machine machine;
  machine.WriteState(seed);

  const auto halt_result = machine.Step(4);
  const auto halted = machine.ReadState();
  const auto stopped_result = machine.Step(kAllKeys);
  const auto stopped = machine.ReadState();

  Require(halt_result == StepResult::kRetired && halted.is_halted, "HLT must set the halt latch");
  Require(stopped_result == StepResult::kStopped, "halted machine must report stopped");
  Require(stopped == halted, "halted machine must preserve its complete state, including keys");
}

void CheckIllegal(std::span<const std::uint8_t> program) {
  Machine machine;
  machine.LoadImage(program);
  for ([[maybe_unused]] const auto step :
       std::views::iota(std::uint64_t{0}, kStepsBeforeIllegalOpcode)) {
    Require(machine.Step(0) == StepResult::kRetired, "illegal-program setup must retire");
  }
  const auto before = machine.ReadState();

  const auto result = machine.Step(kAllKeys);
  const auto after = machine.ReadState();

  Require(result == StepResult::kIllegal, "illegal opcode must be reported");
  Require(after.program_counter == kPcAfterIllegalInstruction &&
              after.trace_address == kIllegalInstructionPc,
          "illegal fetch must advance PC and capture its address");
  Require(!after.is_halted && after.next_program_counter == before.next_program_counter,
          "illegal fetch must preserve halt latch and nextPC");
  Require(after.keys == kAllKeys, "illegal fetch must latch input keys");
}

void CheckStateTransfer(const State &seed) {
  CheckNoop(seed);
  CheckBoundaryStores(seed);
  CheckHaltedPreservation(seed);
}

} // namespace
} // namespace tara::verilator

int main(int argc, char *argv[]) {
  try {
    constexpr int kArgumentCount = 3; // Two image paths at the command-line boundary.
    if (argc != kArgumentCount) {
      throw std::runtime_error("usage: state-test STATE_IMAGE ILLEGAL_IMAGE");
    }
    const auto image_paths = std::span(argv, static_cast<std::size_t>(argc)).subspan(1);
    const auto seed = tara::verilator::SeedState(tara::verilator::ReadImage(image_paths.front()));
    tara::verilator::CheckStateTransfer(seed);
    tara::verilator::CheckIllegal(tara::verilator::ReadImage(image_paths.back()));
  } catch (const std::exception &error) {
    try {
      std::println(stderr, "{}", error.what());
    } catch (...) {
      // A failed diagnostic still exits with the test's failure status.
      return 1;
    }
    return 1;
  }
}
