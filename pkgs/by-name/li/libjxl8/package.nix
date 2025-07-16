{
  stdenv,
  lib,
  fetchFromGitHub,
  libjxl,
  fetchpatch,
}:

libjxl.overrideAttrs (
  finalAttrs: previousAttrs: {
    version = "0.8.2";
    src = fetchFromGitHub {
      owner = "libjxl";
      repo = "libjxl";
      rev = "v${finalAttrs.version}";
      hash = "sha256-I3PGgh0XqRkCFz7lUZ3Q4eU0+0GwaQcVb6t4Pru1kKo=";
      fetchSubmodules = true;
    };
    patches = [
      # Add missing <atomic> content to fix gcc compilation for RISCV architecture
      # https://github.com/libjxl/libjxl/pull/2211
      (fetchpatch {
        url = "https://github.com/libjxl/libjxl/commit/22d12d74e7bc56b09cfb1973aa89ec8d714fa3fc.patch";
        hash = "sha256-X4fbYTMS+kHfZRbeGzSdBW5jQKw8UN44FEyFRUtw0qo=";
      })
    ];
    postPatch = ''
      # Fix multiple definition errors by using C++17 instead of C++11
      substituteInPlace CMakeLists.txt \
        --replace "set(CMAKE_CXX_STANDARD 11)" "set(CMAKE_CXX_STANDARD 17)"
    '';
    postInstall = "";

    cmakeFlags =
      [
        "-DJPEGXL_FORCE_SYSTEM_BROTLI=ON"
        "-DJPEGXL_FORCE_SYSTEM_HWY=ON"
        "-DJPEGXL_FORCE_SYSTEM_GTEST=ON"
      ]
      ++ lib.optionals stdenv.hostPlatform.isStatic [
        "-DJPEGXL_STATIC=ON"
      ]
      ++ lib.optionals stdenv.hostPlatform.isAarch32 [
        "-DJPEGXL_FORCE_NEON=ON"
      ];
  }
)
