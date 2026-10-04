# The command line shared by tara-c and tara-ocaml, checked against tests/golden/cli.

# Run an emulator with ARGS; compare its output and exit status with tests/golden/cli/GOLDEN.out.
[private]
cli-expect emulator golden status *args:
    diff -u <(cat "tests/golden/cli/$2.out"; echo "exit $3") <(set +e; "$1" "${@:4}"; echo "exit $?")

# Run an emulator with ARGS; expect exit status 1 and nothing on stdout.
[private]
cli-reject emulator *args:
    diff -u <(echo "exit 1") <(set +e; "$1" "${@:2}" 2> /dev/null; echo "exit $?")

# --keys holds the input lines for the whole run, in decimal or hex.
[group('test')]
cli-keys emulator: \
    (cli-expect emulator "keys" "0" "--keys" "21" "tests/programs/keys.hex") \
    (cli-expect emulator "keys" "0" "--keys" "0x15" "tests/programs/keys.hex")

# --key-script sets the input lines from given retirement counts on; --keys holds them before.
[group('test')]
cli-key-script emulator: (cli-expect emulator "key-script" "0" \
    "--keys" "1" "--key-script" "tests/programs/keys.script" "tests/programs/keys.hex")

# --fb prints the framebuffer after the dump, top row first.
[group('test')]
cli-fb emulator: (cli-expect emulator "pixels-fb" "0" "--fb" "tests/programs/pixels.hex")

# -n and --max-steps end the run after a number of retirements, with status limit.
[group('test')]
cli-limit emulator: \
    (cli-expect emulator "spin-limit" "3" "-n" "10" "tests/programs/spin.hex") \
    (cli-expect emulator "spin-limit" "3" "--max-steps" "10" "tests/programs/spin.hex")

# -t and --trace print a line per step before the dump.
[group('test')]
cli-trace emulator: \
    (cli-expect emulator "spin-trace" "3" "-t" "-n" "2" "tests/programs/spin.hex") \
    (cli-expect emulator "spin-trace" "3" "--trace" "-n" "2" "tests/programs/spin.hex")

# An unassigned opcode ends the run with status illegal; its step still has a trace line.
[group('test')]
cli-illegal emulator: \
    (cli-expect emulator "illegal" "4" "tests/programs/illegal.hex") \
    (cli-expect emulator "illegal-trace" "4" "-t" "tests/programs/illegal.hex")

# --disasm-all disassembles every word, 0000 to ffff, in order.
[group('test')]
cli-disasm-words emulator:
    "$1" --disasm-all | cut -d ' ' -f 1 | cmp - <(printf '%04x\n' $(seq 0 65535))

# --disasm-all agrees with a sample checked against the TARA Studio assembler.
[group('test')]
cli-disasm-sample emulator:
    "$1" --disasm-all | grep -Fx -f tests/golden/cli/disasm.sample | diff -u tests/golden/cli/disasm.sample -

# Usage errors, unreadable images, bad key scripts and -i without a terminal exit with status 1.
[group('test')]
cli-errors emulator: \
    (cli-reject emulator) \
    (cli-reject emulator "--bogus" "tests/programs/keys.hex") \
    (cli-reject emulator "--keys" "32" "tests/programs/keys.hex") \
    (cli-reject emulator "-n" "-1" "tests/programs/keys.hex") \
    (cli-reject emulator "tests/programs/missing.hex") \
    (cli-reject emulator "--key-script" "tests/programs/unordered.script" "tests/programs/keys.hex") \
    (cli-reject emulator "--interactive" "tests/programs/spin.hex")

# Check an emulator's command line against the shared contract.
[group('test')]
cli emulator: \
    (cli-keys emulator) \
    (cli-key-script emulator) \
    (cli-fb emulator) \
    (cli-limit emulator) \
    (cli-trace emulator) \
    (cli-illegal emulator) \
    (cli-disasm-words emulator) \
    (cli-disasm-sample emulator) \
    (cli-errors emulator)
