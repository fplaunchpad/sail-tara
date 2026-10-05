#ifndef TARA_VERILATOR_TERMINAL_H
#define TARA_VERILATOR_TERMINAL_H

#include <array>
#include <atomic>
#include <csignal> // IWYU pragma: keep (POSIX declarations come from signal.h)
#include <cstddef>
#include <string>
#include <string_view>

#include <termios.h>

#include "input.h"

namespace tara::verilator {

class Terminal {
public:
  Terminal();
  ~Terminal();
  Terminal(const Terminal &) = delete;
  auto operator=(const Terminal &) -> Terminal & = delete;
  Terminal(Terminal &&) = delete;
  auto operator=(Terminal &&) -> Terminal & = delete;

  void Write(std::string_view text) const;
  [[nodiscard]] auto Read(Time deadline) const -> std::string;
  [[nodiscard]] auto WasResized() const -> bool;

private:
  void InstallFatalHandlers();
  void InstallResizeHandler();
  void OpenScreen();
  void RestoreScreen();
  void RestoreAfterSignal();
  void RestoreHandlers();
  [[nodiscard]] auto ReadAvailable() const -> std::string;
  static void OnFatalSignal(int signal);
  static void OnResize(int signal);

  // Plain int and POSIX structs belong to the signal/terminal API boundary.
  struct Handler {
    int signal;
    struct sigaction previous;
  };

  static constexpr std::size_t kHandlerCapacity = 10;
  std::array<Handler, kHandlerCapacity> handlers_{};
  std::size_t handler_count_{};
  termios original_{};
  std::atomic<bool> is_open_;
  static std::atomic<Terminal *> active_;
  static std::atomic<bool> has_resized_;
};

} // namespace tara::verilator

#endif
