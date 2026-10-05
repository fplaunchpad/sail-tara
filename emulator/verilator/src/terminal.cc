#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <csignal> // IWYU pragma: keep (POSIX declarations come from signal.h)
#include <cstddef>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>

#include <fcntl.h>
#include <poll.h> // IWYU pragma: keep (poll is declared by sys/poll.h)
#include <termios.h>
#include <unistd.h>

#include "keyboard.h"
#include "terminal.h"
#include "terminal_codes.h"

namespace tara::verilator {
namespace {

constexpr auto kEnterAlternateScreen =
    JoinSequences(ControlSequence("?1049h"), ControlSequence("?25l"));
constexpr auto kLeaveAlternateScreen =
    JoinSequences(kResetAttributes, ControlSequence("?25h"), ControlSequence("?1049l"));
constexpr std::array kFatalSignals{SIGHUP,  SIGINT, SIGQUIT, SIGTERM, SIGABRT,
                                   SIGSEGV, SIGBUS, SIGFPE,  SIGILL};
constexpr std::size_t kCleanupWriteAttempts = 4;
constexpr int kCleanupWaitMilliseconds = 50;
constexpr std::size_t kReadBytes = 256;

static_assert(std::atomic<Terminal *>::is_always_lock_free);
static_assert(std::atomic<bool>::is_always_lock_free);

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

termios MakeRawSettings(termios settings) {
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

void WriteCleanupSequence(int timeout_ms) {
  // POSIX exposes fixed file-status operations through fcntl's variadic API.
  // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg)
  const auto original_flags = fcntl(STDOUT_FILENO, F_GETFL);
  // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg)
  if (original_flags < 0 || fcntl(STDOUT_FILENO, F_SETFL, original_flags | O_NONBLOCK) < 0) {
    return;
  }

  std::string_view remaining(kLeaveAlternateScreen);
  // The attempt budget bounds both EINTR retries and waits on a stalled terminal.
  for (std::size_t attempt = 0; attempt < kCleanupWriteAttempts && !remaining.empty(); ++attempt) {
    const auto written = write(STDOUT_FILENO, remaining.data(), remaining.size());
    if (written > 0) {
      remaining.remove_prefix(static_cast<std::size_t>(written));
    } else if (written < 0 && WouldBlock(errno)) {
      pollfd output{.fd = STDOUT_FILENO, .events = POLLOUT, .revents = 0};
      if (poll(&output, 1, timeout_ms) <= 0) {
        break;
      }
    } else if (written == 0 || errno != EINTR) {
      break;
    }
  }

  // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg)
  fcntl(STDOUT_FILENO, F_SETFL, original_flags);
}

} // namespace

std::atomic<Terminal *> Terminal::active_terminal_{};
std::atomic<bool> Terminal::has_pending_resize_{};

Terminal::Terminal() {
  if (isatty(STDIN_FILENO) == 0 || isatty(STDOUT_FILENO) == 0) {
    throw std::runtime_error("play needs a terminal on standard input and output");
  }
  if (tcgetattr(STDIN_FILENO, &original_settings_) != 0) {
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
    saved_handlers_[saved_handler_count_++] = {.signal = signal, .previous_action = previous};
  }
}

void Terminal::InstallResizeHandler() {
  struct sigaction resize{};
  resize.sa_handler = OnResize;
  resize.sa_flags = SA_RESTART;
  sigemptyset(&resize.sa_mask);
  auto &handler = saved_handlers_[saved_handler_count_];
  handler.signal = SIGWINCH;
  if (sigaction(SIGWINCH, &resize, &handler.previous_action) != 0) {
    ThrowSystemError("install resize handler");
  }
  ++saved_handler_count_;
}

void Terminal::OpenScreen() {
  active_terminal_.store(this);
  is_screen_active_.store(true);
  const auto raw_settings = MakeRawSettings(original_settings_);
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw_settings) != 0) {
    ThrowSystemError("set terminal to raw mode");
  }
  Write(std::string_view(kEnterAlternateScreen));
}

Terminal::~Terminal() {
  RestoreScreen();
  RestoreHandlers();
}

void Terminal::RestoreScreen() {
  sigset_t signals_to_block{};
  sigset_t original_mask{};
  sigfillset(&signals_to_block);
  const bool has_blocked_signals =
      pthread_sigmask(SIG_BLOCK, &signals_to_block, &original_mask) == 0;
  if (is_screen_active_.exchange(false)) {
    active_terminal_.store(nullptr);
    tcsetattr(STDIN_FILENO, TCSANOW, &original_settings_);
    WriteCleanupSequence(kCleanupWaitMilliseconds);
  }

  if (has_blocked_signals) {
    pthread_sigmask(SIG_SETMASK, &original_mask, nullptr);
  }
}

void Terminal::RestoreAfterSignal() {
  if (!is_screen_active_.exchange(false)) {
    return;
  }
  tcsetattr(STDIN_FILENO, TCSANOW, &original_settings_);
  WriteCleanupSequence(0);
}

void Terminal::RestoreHandlers() {
  for (const auto &handler : std::span(saved_handlers_).first(saved_handler_count_)) {
    sigaction(handler.signal, &handler.previous_action, nullptr);
  }
  saved_handler_count_ = 0;
}

void Terminal::OnFatalSignal(int signal) {
  if (auto *terminal = active_terminal_.exchange(nullptr)) {
    terminal->RestoreAfterSignal();
  }
  if (raise(signal) != 0) {
    _exit(1);
  }
}

void Terminal::OnResize([[maybe_unused]] int signal) { has_pending_resize_.store(true); }

bool Terminal::ConsumeResize() { return has_pending_resize_.exchange(false); }

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

std::string Terminal::Read(TimePoint deadline) const {
  const auto delay = std::chrono::ceil<std::chrono::milliseconds>(deadline - Clock::now());
  // poll takes an int millisecond timeout; frame deadlines are at most one frame away.
  const auto timeout_ms =
      static_cast<int>(std::max(delay.count(), std::chrono::milliseconds::rep{0}));
  pollfd input{.fd = STDIN_FILENO, .events = POLLIN, .revents = 0};
  const auto poll_result = poll(&input, 1, timeout_ms);
  if (poll_result == 0 || (poll_result < 0 && errno == EINTR)) {
    return {};
  }
  if (poll_result < 0) {
    ThrowSystemError("wait for terminal input");
  }
  return ReadAvailable();
}

std::string Terminal::ReadAvailable() const {
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
