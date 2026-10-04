#include "terminal.h"

#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include "report.h"

/* Enter the alternate screen and hide the cursor; and the way back, which also resets the colors
 * a frame cut short may have left. */
#define ENTER_SCREEN "\x1b[?1049h\x1b[?25l"
#define LEAVE_SCREEN "\x1b[0m\x1b[?25h\x1b[?1049l"

/* The signals that end the process by default: those a terminal session can end in, and those of
 * a crash, which must not leave the terminal raw either. */
static const int FATAL_SIGNALS[] = {SIGHUP,  SIGINT, SIGQUIT, SIGTERM, SIGABRT,
                                    SIGSEGV, SIGBUS, SIGFPE,  SIGILL};

static struct termios original;       /* the settings before terminal_open */
static volatile sig_atomic_t is_open; /* terminal_open has changed the terminal; put it back */
static volatile sig_atomic_t resized;

bool terminal_write(const char *data, size_t length) {
  while (length > 0) {
    ssize_t written = write(STDOUT_FILENO, data, length);
    if (written > 0) {
      data += written;
      length -= (size_t)written;
    } else if (written < 0 && errno == EINTR) {
      continue;
    } else if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      struct pollfd output = {.fd = STDOUT_FILENO, .events = POLLOUT};
      poll(&output, 1, -1);
    } else {
      return false;
    }
  }
  return true;
}

/* Safe in a signal handler. A signal that comes in the middle of the restoring restores it all
 * over again before it ends the process, which does no harm. */
void terminal_close(void) {
  if (!is_open)
    return;

  int saved_errno = errno;
  terminal_write(LEAVE_SCREEN, sizeof LEAVE_SCREEN - 1);
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &original);
  is_open = 0;
  errno = saved_errno;
}

/* Restore the terminal, then let the signal end the process: SA_RESETHAND has made its action the
 * default one. */
static void on_fatal_signal(int signal_number) {
  terminal_close();
  raise(signal_number);
}

static void on_resize(int signal_number) {
  (void)signal_number;
  resized = 1;
}

static void install_handlers(void) {
  struct sigaction fatal = {.sa_handler = on_fatal_signal, .sa_flags = SA_RESETHAND};
  sigfillset(&fatal.sa_mask);
  for (size_t i = 0; i < sizeof FATAL_SIGNALS / sizeof *FATAL_SIGNALS; ++i) {
    /* A signal that was ignored at the start (nohup, a background job) stays ignored. */
    struct sigaction current;
    if (sigaction(FATAL_SIGNALS[i], NULL, &current) == 0 && current.sa_handler != SIG_IGN)
      sigaction(FATAL_SIGNALS[i], &fatal, NULL);
  }

  struct sigaction resize = {.sa_handler = on_resize, .sa_flags = SA_RESTART};
  sigemptyset(&resize.sa_mask);
  sigaction(SIGWINCH, &resize, NULL);
}

/* The settings of cfmakeraw, which POSIX lacks: no echo, no line editing, no signals or flow
 * control from keys, no output processing, and a read waits for one byte. */
static void make_raw(struct termios *settings) {
  settings->c_iflag &=
      ~(tcflag_t)(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
  settings->c_oflag &= ~(tcflag_t)OPOST;
  settings->c_lflag &= ~(tcflag_t)(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  settings->c_cflag &= ~(tcflag_t)(CSIZE | PARENB);
  settings->c_cflag |= CS8;
  settings->c_cc[VMIN] = 1;
  settings->c_cc[VTIME] = 0;
}

bool terminal_attached(void) { return isatty(STDIN_FILENO) && isatty(STDOUT_FILENO); }

bool terminal_open(void) {
  if (tcgetattr(STDIN_FILENO, &original) != 0)
    return report_error("cannot read the terminal settings: %s", strerror(errno));

  struct termios raw = original;
  make_raw(&raw);
  install_handlers();
  atexit(terminal_close);

  is_open = 1;
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0 ||
      !terminal_write(ENTER_SCREEN, sizeof ENTER_SCREEN - 1)) {
    int error = errno;
    terminal_close();
    return report_error("cannot set up the terminal: %s", strerror(error));
  }
  return true;
}

bool terminal_resized(void) {
  bool was_resized = resized;
  resized = 0;
  return was_resized;
}

ssize_t terminal_read(uint8_t *buffer, size_t size, int timeout_ms) {
  struct pollfd input = {.fd = STDIN_FILENO, .events = POLLIN};
  int ready = poll(&input, 1, timeout_ms);
  if (ready < 0)
    return errno == EINTR ? 0 : -1;
  if (ready == 0)
    return 0;

  ssize_t count = read(STDIN_FILENO, buffer, size);
  if (count > 0)
    return count;
  return count < 0 && (errno == EINTR || errno == EAGAIN) ? 0 : -1;
}
