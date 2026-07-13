// mayhem/fuzz_tinyexr.cc — in-process libFuzzer harness for TinyEXR's v1 loader.
//
// The archived Mayhem target `test-tinyexr` fuzzed the file-input CLI `test_tinyexr @@`,
// whose only work is `LoadEXR(..., input_filename, ...)` (plus the lower-level
// Parse*/LoadEXRImage* calls). A raw file-input CLI re-opens/re-reads the file on every
// iteration; converting it to an in-process libFuzzer harness over the SAME code path
// (skill-endorsed) drives many more iterations per second while exercising the identical
// TinyEXR decode API. It mirrors upstream's own harness (test/fuzzer/fuzz.cc) and adds the
// high-level LoadEXRFromMemory path that the CLI's LoadEXR() used.
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#define TINYEXR_IMPLEMENTATION
#include "tinyexr.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  // 1) Version -> single-part header -> image (upstream fuzz.cc code path).
  EXRVersion exr_version;
  if (ParseEXRVersionFromMemory(&exr_version, data, size) == TINYEXR_SUCCESS) {
    EXRHeader exr_header;
    InitEXRHeader(&exr_header);
    if (ParseEXRHeaderFromMemory(&exr_header, &exr_version, data, size, NULL) ==
        TINYEXR_SUCCESS) {
      EXRImage exr_image;
      InitEXRImage(&exr_image);
      if (LoadEXRImageFromMemory(&exr_image, &exr_header, data, size, NULL) ==
          TINYEXR_SUCCESS) {
        FreeEXRImage(&exr_image);
      }
    }
    FreeEXRHeader(&exr_header);
  }

  // 2) High-level RGBA loader — the exact call the archived CLI target made
  //    (LoadEXR on the input file), fed from memory.
  {
    float *rgba = NULL;
    int width = 0, height = 0;
    const char *err = NULL;
    if (LoadEXRFromMemory(&rgba, &width, &height, data, size, &err) ==
        TINYEXR_SUCCESS) {
      free(rgba);
    }
    if (err) FreeEXRErrorMessage(err);
  }

  return 0;
}
