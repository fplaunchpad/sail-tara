#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>

#include "Vtara_step.h"
#include "sail.h" // IWYU pragma: keep (the generated tara.h requires Sail's runtime types)
#include "verilated.h"
extern "C" {
#include "tara.h"
// Defined in Sail's generated C, but not declared in its header.
void model_init();
void model_fini();
}

#include "machine.h"

namespace tara::verilator {
namespace {

class HostModel {
public:
  HostModel() {
    model_init();
    zhost_reset(UNIT);
  }

  ~HostModel() { model_fini(); }

  HostModel(const HostModel &) = delete;
  HostModel &operator=(const HostModel &) = delete;
  HostModel(HostModel &&) = delete;
  HostModel &operator=(HostModel &&) = delete;
};

class SailText {
public:
  SailText() { CREATE(sail_string)(&value_); }

  ~SailText() { KILL(sail_string)(&value_); }

  SailText(const SailText &) = delete;
  SailText &operator=(const SailText &) = delete;
  SailText(SailText &&) = delete;
  SailText &operator=(SailText &&) = delete;

  [[nodiscard]] sail_string *OutputPointer() { return &value_; }

  [[nodiscard]] std::string Copy() const { return value_; }

private:
  sail_string value_{};
};

void LoadInputs(Vtara_step &circuit, std::uint8_t keys) {
  const auto registers = std::span(zGPR.data, zGPR.len);
  const auto memory = std::span(zMEM.data, zMEM.len);
  std::ranges::transform(registers, circuit.in_GPR.data(),
                         [](std::uint64_t value) { return static_cast<std::uint16_t>(value); });
  std::ranges::transform(memory, circuit.in_MEM.data(),
                         [](std::uint64_t value) { return static_cast<std::uint8_t>(value); });

  circuit.arg0 = keys;
  circuit.in_PC = static_cast<std::uint16_t>(zPC);
  circuit.in_HALTED = static_cast<std::uint8_t>(zHALTED);
  circuit.in_KEYS = static_cast<std::uint8_t>(zKEYS);
  circuit.in_nextPC = static_cast<std::uint16_t>(znextPC);
  circuit.in_trace_pc = static_cast<std::uint16_t>(ztrace_pc);
  circuit.in_trace_word = static_cast<std::uint16_t>(ztrace_word);
}

void StoreOutputs(const Vtara_step &circuit) {
  std::ranges::copy(std::span(circuit.out_GPR.data(), circuit.out_GPR.size()), zGPR.data);
  std::ranges::copy(std::span(circuit.out_MEM.data(), circuit.out_MEM.size()), zMEM.data);
  zPC = circuit.out_PC;
  zHALTED = circuit.out_HALTED != 0;
  zKEYS = circuit.out_KEYS;
  znextPC = circuit.out_nextPC;
  ztrace_pc = circuit.out_trace_pc;
  ztrace_word = circuit.out_trace_word;
}

} // namespace

class Machine::Impl {
public:
  Impl() {
    context_.threads(1);
    circuit_ = std::make_unique<Vtara_step>(&context_);
  }

  ~Impl() { circuit_->final(); }

  Impl(const Impl &) = delete;
  Impl &operator=(const Impl &) = delete;
  Impl(Impl &&) = delete;
  Impl &operator=(Impl &&) = delete;

private:
  friend class Machine;
  HostModel host_helpers_;
  VerilatedContext context_;
  std::unique_ptr<Vtara_step> circuit_;
};

Machine::Machine() : impl_(std::make_unique<Impl>()) {}

Machine::~Machine() = default;

void Machine::LoadImage(std::span<const std::uint8_t> image) {
  if (image.size() > kMemoryBytes) {
    throw std::runtime_error("image is larger than TARA memory");
  }
  std::ranges::copy(image, zMEM.data);
}

StepResult Machine::Step(std::uint8_t keys) {
  auto &circuit = *impl_->circuit_;
  LoadInputs(circuit, keys);
  circuit.eval();
  StoreOutputs(circuit);
  return static_cast<StepResult>(circuit.sail_return);
}

State Machine::ReadState() const {
  State state;
  std::ranges::transform(std::span(zGPR.data, zGPR.len), state.registers.begin(),
                         [](std::uint64_t value) { return static_cast<std::uint16_t>(value); });
  std::ranges::transform(std::span(zMEM.data, zMEM.len), state.memory.begin(),
                         [](std::uint64_t value) { return static_cast<std::uint8_t>(value); });
  state.program_counter = static_cast<std::uint16_t>(zPC);
  state.next_program_counter = static_cast<std::uint16_t>(znextPC);
  state.trace_address = static_cast<std::uint16_t>(ztrace_pc);
  state.trace_word = static_cast<std::uint16_t>(ztrace_word);
  state.keys = static_cast<std::uint8_t>(zKEYS);
  state.is_halted = zHALTED;
  return state;
}

void Machine::WriteState(const State &state) {
  std::ranges::copy(state.registers, zGPR.data);
  std::ranges::copy(state.memory, zMEM.data);
  zPC = state.program_counter;
  znextPC = state.next_program_counter;
  ztrace_pc = state.trace_address;
  ztrace_word = state.trace_word;
  zKEYS = state.keys;
  zHALTED = state.is_halted;
}

std::uint16_t Machine::ProgramCounter() const { return static_cast<std::uint16_t>(zPC); }

bool Machine::IsHalted() const { return zHALTED; }

bool Machine::IsPixelSet(std::size_t pixel_x, std::size_t pixel_y) const {
  return zhost_pixel(pixel_x, pixel_y);
}

std::string Machine::Trace() const {
  SailText text;
  zhost_trace(text.OutputPointer(), UNIT);
  return text.Copy();
}

std::string Machine::Dump() const {
  SailText text;
  zhost_dump(text.OutputPointer(), UNIT);
  return text.Copy();
}

std::string Machine::Disassemble(std::uint16_t word) const {
  SailText text;
  zhost_disasm(text.OutputPointer(), word);
  return text.Copy();
}

} // namespace tara::verilator
