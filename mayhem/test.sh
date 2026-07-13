#!/usr/bin/env bash
#
# mayhem/test.sh — run TinyEXR's upstream test suite (what upstream CI runs) and emit CTRF.
#
#   1. build/test_exr_v3   the v3 C unit-test suite (prebuilt by mayhem/build.sh via
#                          `make test-c`; 246 CHECK assertions covering the reader/writer,
#                          every compression codec, streams, wavelets, SIMD kernels).
#                          BEHAVIORAL: we parse its "<N> passed, <M> failed" result line —
#                          a neutered exit(0) binary prints nothing and FAILS here.
#   2. make c11-gate       upstream's strict-C11 -Werror compile gate over src/*.c.
#   3. make tools-test     upstream's self-contained tool gates (texcomp/resize/texpipe/
#                          envmap — 12 sub-gates), asserted on its final marker line.
#
# NOT integrated (recorded for the manifest): test/unit/tester.cc — the legacy v1 Catch
# suite (58 TEST_CASEs) needs the external openexr-images repository (../../../openexr-images)
# which upstream does not vendor and upstream CI does not run.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

passed=0; failed=0

# emit_ctrf <tool> <passed> <failed> [skipped]
emit_ctrf() {
  local tool="$1" p="$2" f="$3" s="${4:-0}"
  local tests=$(( p + f + s ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $p, "failed": $f, "pending": 0, "skipped": $s, "other": 0 }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$p" "$f" "$s"
  [ "$f" -eq 0 ]
}

# 1) v3 C unit tests — run the PREBUILT runner and assert its printed result line.
V3=build/test_exr_v3
if [ -x "$V3" ]; then
  out="$(ASAN_OPTIONS=detect_leaks=0 "$V3" 2>&1)" || true
  line="$(printf '%s\n' "$out" | grep -E '^[0-9]+ passed, [0-9]+ failed$' | tail -1)"
  if [ -n "$line" ]; then
    p="$(printf '%s' "$line" | awk '{print $1}')"
    f="$(printf '%s' "$line" | awk '{print $3}')"
    passed=$((passed + p)); failed=$((failed + f))
    echo "test.sh: test_exr_v3 -> $line"
    [ "$f" -eq 0 ] || printf '%s\n' "$out" | grep -E 'FAIL' | head -20
  else
    echo "test.sh: test_exr_v3 produced NO result line (neutered or crashed?)"
    failed=$((failed + 1))
  fi
else
  echo "test.sh: $V3 missing — build.sh must build it (not rebuilding here)"
  failed=$((failed + 1))
fi

# 2) strict-C11 compile gate (upstream CI job).
if make c11-gate 2>&1 | grep -q 'pure-C11 gate: OK'; then
  echo "test.sh: c11-gate ok"; passed=$((passed + 1))
else
  echo "test.sh: c11-gate FAILED"; failed=$((failed + 1))
fi

# 3) tool gates (upstream CI job) — asserted on the Makefile's final marker line.
if make -j"${MAYHEM_JOBS:-$(nproc)}" tools-test 2>&1 | grep -q 'tools-test: all self-contained tool gates passed'; then
  echo "test.sh: tools-test ok"; passed=$((passed + 1))
else
  echo "test.sh: tools-test FAILED"; failed=$((failed + 1))
fi

echo "test.sh: passed=$passed failed=$failed"
emit_ctrf tinyexr "$passed" "$failed"
