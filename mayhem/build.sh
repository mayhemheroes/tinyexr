#!/usr/bin/env bash
#
# mayhem/build.sh — build TinyEXR's fuzz target + upstream test suite.
#
# Fuzz target `test-tinyexr` (historical Mayhem target name): an in-process libFuzzer
# harness (mayhem/fuzz_tinyexr.cc) over the v1 single-header decoder (tinyexr.h +
# deps/miniz). The library implementation is compiled INTO the harness TU with
# $SANITIZER_FLAGS + $DEBUG_FLAGS, so the fuzzed code itself is instrumented and
# carries DWARF < 4 symbols.
#
# Test suite: upstream's own Makefile suites (what upstream CI runs) —
#   make c11-gate   pure-C11 -Werror compile gate over src/*.c        (run by test.sh)
#   make test-c     v3 C unit tests -> build/test_exr_v3 (246 checks) (built here; the
#                   .PHONY recipe also runs it once, an extra build-time validation;
#                   test.sh re-runs the prebuilt binary and asserts its output)
#   make tools-test self-contained tool gates (texcomp/resize/texpipe/envmap)
#                   (run by test.sh)
# The upstream Makefile chooses its own (non-sanitized/ASan-for-tests) flags — an
# independent build from the fuzz target above.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

mkdir -p build-mayhem

# 1+2) Fuzz harness (library implementation compiled in, sanitized + DWARF-3).
#      miniz is the zlib backend tinyexr.h's v1 decoder uses; compile it with the same
#      sanitizer/debug flags so it is instrumented too.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -I"$SRC/deps/miniz" \
    -c "$SRC/deps/miniz/miniz.c" -o build-mayhem/miniz.o
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -O1 -std=c++11 \
    -I"$SRC" -I"$SRC/deps/miniz" \
    "$SRC/mayhem/fuzz_tinyexr.cc" build-mayhem/miniz.o \
    -o "$SRC/test-tinyexr"

# Standalone run-once reproducer (no libFuzzer runtime). C++ harness => compile the
# standalone driver as C first so LLVMFuzzerTestOneInput keeps C linkage.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build-mayhem/standalone_main.o
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -std=c++11 \
    -I"$SRC" -I"$SRC/deps/miniz" \
    "$SRC/mayhem/fuzz_tinyexr.cc" build-mayhem/standalone_main.o build-mayhem/miniz.o \
    -o "$SRC/test-tinyexr-standalone"

# 3) Upstream test suite (independent build, upstream's own Makefile flags).
#    `test-c` is .PHONY: it links build/test_exr_v3 and runs it once (build-time
#    validation); mayhem/test.sh re-runs the prebuilt binary and asserts its output.
make -j"$MAYHEM_JOBS" test-c

echo "build.sh: built test-tinyexr (fuzzer), test-tinyexr-standalone, build/test_exr_v3 (upstream suite)"
