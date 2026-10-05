#ifndef TARA_VERILATOR_TERMINAL_H
#define TARA_VERILATOR_TERMINAL_H

#include <array>
#include <atomic>
#include <csignal> // IWYU pragma: keep (POSIX declarations come from signal.h)
#include <cstddef>
#include <string>
#include <string_view>

#include <termios.h>

#include "keyboard.h"

namespace tara::verilator {

class Terminal {
public:
  Terminal();
  ~Terminal();
  Terminal(const Terminal &) = delete;
  Terminal &operator=(const Terminal &) = delete;
  Terminal(Terminal &&) = delete;
  Terminal &operator=(Terminal &&) = delete;

  void Write(std::string_view text) const;
  [[nodiscard]] std::string Read(TimePoint deadline) const;
  [[nodiscard]] bool ConsumeResize();

private:
  void InstallFatalHandlers();
  void InstallResizeHandler();
  void OpenScreen();
  void RestoreScreen();
  void RestoreAfterSignal();
  void RestoreHandlers();
  [[nodiscard]] std::string ReadAvailable() const;
  static void OnFatalSignal(int signal);
  static void OnResize(int signal);

  // Plain int and POSIX structs belong to the signal/terminal API boundary.
  struct SavedSignalHandler {
    int signal;
    struct sigaction previous_action;
  };

  static constexpr std::size_t kHandlerCapacity = 10;
  std::array<SavedSignalHandler, kHandlerCapacity> saved_handlers_{};
  std::size_t saved_handler_count_{};
  termios original_settings_{};
  std::atomic<bool> is_screen_active_;
  static std::atomic<Terminal *> active_terminal_;
  static std::atomic<bool> has_pending_resize_;
};

} // namespace tara::verilator

#endif
