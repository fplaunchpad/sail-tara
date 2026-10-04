# Compare an emulator's final dump of the Fibonacci program with the golden file.
[group('test')]
golden-dump emulator:
    "$1" tests/programs/fibonacci.hex | diff -u tests/golden/fibonacci.dump -

# Compare an emulator's trace of the Fibonacci program with the golden files.
[group('test')]
golden-trace emulator:
    "$1" -t tests/programs/fibonacci.hex | diff -u <(cat tests/golden/fibonacci.trace tests/golden/fibonacci.dump) -

# Compare an emulator's dump and trace of the Fibonacci program with the golden files.
[group('test')]
golden emulator: (golden-dump emulator) (golden-trace emulator)
