# Sail 0.20.3 target. Compilation/execution of this revision is not yet validated.
SHELL := /bin/sh
.DEFAULT_GOAL := check
SAIL ?= sail
CC ?= cc
CFLAGS ?= -O2
LDLIBS ?= -lgmp -lz
SAIL_LIB_DIR ?=
BUILD := build

.PHONY: require-sail require-runtime check c test rocq audit clean

require-sail:
	@command -v "$(SAIL)" >/dev/null 2>&1 || { \
	  echo 'ERROR: Sail compiler not found. No Sail validation was performed.' >&2; \
	  exit 127; \
	}

require-runtime:
	@test -n "$(SAIL_LIB_DIR)" && test -f "$(SAIL_LIB_DIR)/sail.h" || { \
	  echo 'ERROR: set SAIL_LIB_DIR to the matching Sail C runtime directory containing sail.h.' >&2; \
	  exit 2; \
	}

check: require-sail
	$(SAIL) --just-check tara.sail
	$(SAIL) --just-check tests/test_tara.sail

c: check
	mkdir -p $(BUILD)
	$(SAIL) -c -O tests/test_tara.sail -o $(BUILD)/tara_tests

test: c require-runtime
	$(CC) $(CFLAGS) -I"$(SAIL_LIB_DIR)" $(BUILD)/tara_tests.c "$(SAIL_LIB_DIR)"/*.c $(LDLIBS) -o $(BUILD)/tara_tests
	./$(BUILD)/tara_tests

# Definition generation only, not a Rocq build or a correctness proof.
rocq: check
	mkdir -p $(BUILD)/rocq
	$(SAIL) -coq tara.sail -o $(BUILD)/rocq/tara

# A restricted source audit, NOT a Sail parser, interpreter or typechecker.
audit:
	python3 validation/review_source.py

clean:
	rm -rf $(BUILD)
