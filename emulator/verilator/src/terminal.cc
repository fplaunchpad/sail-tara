#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>

#include <poll.h> // IWYU pragma: keep (poll is declared by sys/poll.h)
#include <signal.h>
#include <termios.h>
#include <unistd.h>

#include "input.h"
#include "terminal.h"

namespace tara::verilator {
namespace {

constexpr std::string_view kEnterScreen = "\x1b[?1049h\x1b[?25l";
constexpr std::string_view kLeaveScreen = "\x1b[0m\x1b[?25h\x1b[?1049l";
constexpr std::array kFatalSignals{SIGHUP,  SIGINT, SIGQUIT, SIGTERM, SIGABRT,
                                   SIGSEGV, SIGBUS, SIGFPE,  SIGILL};

[[noreturn]] void ThrowSystemError(std::string_view operation) {
  throw std::system_error(errno, std::generic_category(), std::string(operation));
}

bool WouldBlock(int error) {
  return error == EAGAIN
#if EWOULDBLOCK != EAGAIN
         || error == EWOULDBLOCK
#endif
      ;
}

termios RawSettings(termios settings) {
  settings.c_iflag &=
      ~static_cast<tcflag_t>(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
  settings.c_oflag &= ~static_cast<tcflag_t>(OPOST);
  settings.c_lflag &= ~static_cast<tcflag_t>(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  settings.c_cflag &= ~static_cast<tcflag_t>(CSIZE | PARENB);
  settings.c_cflag |= CS8;
  settings.c_cc[VMIN] = 1;
  settings.c_cc[VTIME] = 0;
  return settings;
}

} // namespace

Terminal *Terminal::active_{};
volatile sig_atomic_t Terminal::has_resized_{};

Terminal::Terminal() {
  if (isatty(STDIN_FILENO) == 0 || isatty(STDOUT_FILENO) == 0) {
    throw std::runtime_error("play needs a terminal on standard input and output");
  }
  if (tcgetattr(STDIN_FILENO, &original_) != 0) {
    ThrowSystemError("read terminal settings");
  }
  try {
    InstallFatalHandlers();
    InstallResizeHandler();
    OpenScreen();
  } catch (...) {
    RestoreScreen();
    RestoreHandlers();
    throw;
  }
}

void Terminal::InstallFatalHandlers() {
  for (const auto signal : kFatalSignals) {
    struct sigaction previous{};
    if (sigaction(signal, nullptr, &previous) != 0) {
      ThrowSystemError("read signal handler");
    }
    if (previous.sa_handler == SIG_IGN) {
      continue;
    }
    struct sigaction action{};
    action.sa_handler = OnFatalSignal;
    // POSIX defines this flag as a bit pattern, although sigaction stores it in int.
    action.sa_flags = static_cast<int>(SA_RESETHAND);
    sigfillset(&action.sa_mask);
    if (sigaction(signal, &action, nullptr) != 0) {
      ThrowSystemError("install signal handler");
    }
    handlers_[handler_count_++] = {.signal = signal, .previous = previous};
  }
}

void Terminal::InstallResizeHandler() {
  struct sigaction resize{};
  resize.sa_handler = OnResize;
  resize.sa_flags = SA_RESTART;
  sigemptyset(&resize.sa_mask);
  auto &handler = handlers_[handler_count_];
  handler.signal = SIGWINCH;
  if (sigaction(SIGWINCH, &resize, &handler.previous) != 0) {
    ThrowSystemError("install resize handler");
  }
  ++handler_count_;
}

void Terminal::OpenScreen() {
  active_ = this;
  is_open_ = true;
  const auto raw = RawSettings(original_);
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0) {
    ThrowSystemError("set terminal to raw mode");
  }
  Write(kEnterScreen);
}

Terminal::~Terminal() {
  RestoreScreen();
  RestoreHandlers();
}

void Terminal::RestoreScreen() {
  if (!is_open_) {
    return;
  }
  // Best effort during cleanup, including fatal signals; these calls are async-signal-safe.
  [[maybe_unused]] const auto written =
      write(STDOUT_FILENO, kLeaveScreen.data(), kLeaveScreen.size());
  [[maybe_unused]] const auto restored = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original_);
  is_open_ = false;
  active_ = nullptr;
}

void Terminal::RestoreHandlers() {
  for (const auto &handler : std::span(handlers_).first(handler_count_)) {
    [[maybe_unused]] const auto restored = sigaction(handler.signal, &handler.previous, nullptr);
  }
  handler_count_ = 0;
}

void Terminal::OnFatalSignal(int signal) {
  if (active_ != nullptr) {
    active_->RestoreScreen();
  }
  [[maybe_unused]] const auto raised = raise(signal);
}

void Terminal::OnResize([[maybe_unused]] int signal) { has_resized_ = 1; }

bool Terminal::WasResized() const {
  const bool was_resized = has_resized_ != 0;
  has_resized_ = 0;
  return was_resized;
}

void Terminal::Write(std::string_view text) const {
  while (!text.empty()) {
    const auto written = write(STDOUT_FILENO, text.data(), text.size());
    if (written > 0) {
      text.remove_prefix(static_cast<std::size_t>(written));
    } else if (written < 0 && errno == EINTR) {
      continue;
    } else if (written < 0 && WouldBlock(errno)) {
      pollfd output{.fd = STDOUT_FILENO, .events = POLLOUT, .revents = 0};
      if (poll(&output, 1, -1) < 0 && errno != EINTR) {
        ThrowSystemError("wait for terminal output");
      }
    } else {
      ThrowSystemError("write terminal output");
    }
  }
}

std::string Terminal::Read(Time deadline) const {
  const auto delay = std::chrono::ceil<std::chrono::milliseconds>(deadline - Clock::now());
  // poll takes an int millisecond timeout; frame deadlines are at most one frame away.
  const auto timeout = static_cast<int>(std::max(delay.count(), std::chrono::milliseconds::rep{0}));
  pollfd input{.fd = STDIN_FILENO, .events = POLLIN, .revents = 0};
  const auto ready = poll(&input, 1, timeout);
  if (ready == 0 || (ready < 0 && errno == EINTR)) {
    return {};
  }
  if (ready < 0) {
    ThrowSystemError("wait for terminal input");
  }
  return ReadAvailable();
}

std::string Terminal::ReadAvailable() const {
  constexpr std::size_t kReadBytes = 256;
  std::array<char, kReadBytes> bytes{};
  const auto count = read(STDIN_FILENO, bytes.data(), bytes.size());
  if (count > 0) {
    return {bytes.data(), static_cast<std::size_t>(count)};
  }
  if (count < 0 && (errno == EINTR || WouldBlock(errno))) {
    return {};
  }
  throw std::runtime_error("the terminal is gone");
}

} // namespace tara::verilator
