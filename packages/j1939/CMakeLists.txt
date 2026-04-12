cmake_minimum_required(VERSION 3.21)
project(j1939_plugin VERSION 1.0.0 LANGUAGES CXX C)

# ── Build type default ────────────────────────────────────────────────────────
#
# Without this, an empty CMAKE_BUILD_TYPE produces a no-optimisation,
# no-debug-info build — the worst of both worlds.  Set RelWithDebInfo so
# that a plain `cmake -B build .` gives an optimised binary with symbols.
#
# Override from the command line as usual:
#   cmake -DCMAKE_BUILD_TYPE=Release -B build .

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    message(STATUS "No build type set — defaulting to RelWithDebInfo")
    set(CMAKE_BUILD_TYPE "RelWithDebInfo" CACHE STRING "Build type" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY
        STRINGS "Debug" "Release" "RelWithDebInfo" "MinSizeRel")
endif()

# ── compile_commands.json (for clangd / IDE integration) ─────────────────────

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── ASIO (standalone, header-only, pinned by tag + SHA) ──────────────────────
#
# SHA is the HEAD of the asio-1-30-2 tag.  Verify with:
#   git ls-remote https://github.com/chriskohlhoff/asio refs/tags/asio-1-30-2
#
# To use a local checkout instead of fetching:
#   cmake -DFETCHCONTENT_SOURCE_DIR_ASIO=/path/to/asio/checkout ...

include(FetchContent)

FetchContent_Declare(
    asio
    GIT_REPOSITORY https://github.com/chriskohlhoff/asio.git
    GIT_TAG        12e0ce9e0500bf0f247dbd1ae894272656456079
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(asio)

# ── Dart SDK (required only for the FFI plugin target) ───────────────────────
#
# The DART_SDK option is optional: if not set, j1939_plugin is skipped and
# only j1939_demo is built.  This lets pure C++ unit tests and CI builds work
# without a Dart SDK installed.
#
# Pass the Dart SDK root, which must contain include/dart_native_api.h:
#   cmake -DDART_SDK=/usr/lib/dart ...
#   cmake -DDART_SDK=$(dart --version 2>&1 | ...) ...   # adjust per install
#
# On Ubuntu with the official Dart PPA the path is typically /usr/lib/dart.

option(DART_SDK "Path to the Dart SDK root (enables j1939_plugin target)" "")

if(DART_SDK)
    set(_DART_INCLUDE "${DART_SDK}/include")
    foreach(_hdr IN ITEMS dart_native_api.h dart_api_dl.h)
        if(NOT EXISTS "${_DART_INCLUDE}/${_hdr}")
            message(FATAL_ERROR
                "Dart SDK header/source not found: ${_DART_INCLUDE}/${_hdr}\n"
                "Check that DART_SDK points to the Dart SDK root directory.")
        endif()
    endforeach()
    set(_DART_SDK_FOUND TRUE)
    message(STATUS "Dart SDK found at ${DART_SDK}")
else()
    set(_DART_SDK_FOUND FALSE)
    message(STATUS "DART_SDK not set — skipping j1939_plugin (Dart FFI target)")
endif()

# ── j1939_objects: shared compile settings for all targets ───────────────────
#
# Using an OBJECT library avoids repeating source lists and compile flags.
# Both j1939_plugin and j1939_demo link against this object set.

add_library(j1939_objects OBJECT
    src/can/Socket.cpp
    src/j1939/Transport.cpp
    src/j1939/Network.cpp
    src/j1939/Ecu.cpp
    src/j1939/FastPacket.cpp
    src/j1939/PgnTransport.cpp
)

target_include_directories(j1939_objects PUBLIC src)

target_include_directories(j1939_objects SYSTEM PUBLIC
    ${asio_SOURCE_DIR}/asio/include
)

target_compile_definitions(j1939_objects PUBLIC
    ASIO_STANDALONE
    ASIO_NO_DEPRECATED
    # ASIO_HAS_CO_AWAIT is set automatically by GCC/Clang when C++20 coroutines
    # are available.  Define it explicitly only if your compiler needs the hint.
    # ASIO_HAS_CO_AWAIT
)

target_compile_options(j1939_objects PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wno-missing-field-initializers   # suppress for C-style aggregate init
)

set_target_properties(j1939_objects PROPERTIES
    CXX_STANDARD          23
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON      # required for linking into a .so
)

# ── j1939_plugin: shared library loaded by Dart via DynamicLibrary.open ──────

if(_DART_SDK_FOUND)

    add_library(j1939_plugin SHARED
        ffi/j1939_ffi.cpp
            $<TARGET_OBJECTS:j1939_objects>
    )

    target_include_directories(j1939_plugin PRIVATE
        src
        ${_DART_INCLUDE}
        ${asio_SOURCE_DIR}/asio/include
    )

    target_compile_definitions(j1939_plugin PRIVATE
        ASIO_STANDALONE
        ASIO_NO_DEPRECATED
    )

    target_compile_options(j1939_plugin PRIVATE
        -Wall -Wextra -Wpedantic
        -Wno-missing-field-initializers
    )

    set_target_properties(j1939_plugin PROPERTIES
        CXX_STANDARD              23
        CXX_STANDARD_REQUIRED     ON
            C_STANDARD_REQUIRED       ON
        POSITION_INDEPENDENT_CODE ON
        # Hide all symbols except those explicitly marked extern "C".
        # This prevents clashes if multiple plugins are loaded in the same process.
        VISIBILITY_INLINES_HIDDEN ON
        CXX_VISIBILITY_PRESET     hidden
        C_VISIBILITY_PRESET       hidden
    )

    target_link_libraries(j1939_plugin PRIVATE pthread)

    # ── Install rules ─────────────────────────────────────────────────────────
    #
    # cmake --install build --prefix /usr/local
    #   installs libj1939_plugin.so → <prefix>/lib/
    #   installs j1939_ffi.h        → <prefix>/include/j1939/

    include(GNUInstallDirs)

    install(TARGETS j1939_plugin
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    )
    install(FILES ffi/j1939_ffi.h
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/j1939
    )

endif()

# ── j1939_demo: standalone executable for manual testing on vcan0 ────────────

add_executable(j1939_demo
    src/main.cpp
    $<TARGET_OBJECTS:j1939_objects>
)

target_include_directories(j1939_demo PRIVATE
    src
    ${asio_SOURCE_DIR}/asio/include
)

target_compile_definitions(j1939_demo PRIVATE
    ASIO_STANDALONE
    ASIO_NO_DEPRECATED
)

target_compile_options(j1939_demo PRIVATE
    -Wall -Wextra -Wpedantic
    -Wno-missing-field-initializers
)

set_target_properties(j1939_demo PROPERTIES
    CXX_STANDARD          23
    CXX_STANDARD_REQUIRED ON
)

target_link_libraries(j1939_demo PRIVATE pthread)

# ── Strip Release binaries ────────────────────────────────────────────────────
#
# CMAKE_STRIP is set by CMake to the correct strip binary for the target
# toolchain, handling cross-compilation correctly.

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(_strip_targets j1939_demo)
    if(_DART_SDK_FOUND)
        list(APPEND _strip_targets j1939_plugin)
    endif()

    foreach(_tgt IN LISTS _strip_targets)
        add_custom_command(TARGET ${_tgt} POST_BUILD
            COMMAND "${CMAKE_STRIP}" --strip-unneeded $<TARGET_FILE:${_tgt}>
            COMMENT "Stripping ${_tgt}"
            VERBATIM
        )
    endforeach()
endif()

# ── C++ unit tests (GoogleTest) ──────────────────────────────────────────────
#
# Off by default so hook/build.dart stays fast. CI enables it via:
#   cmake -S . -B build-test -GNinja \
#         -DJ1939_BUILD_TESTING=ON [-DJ1939_ENABLE_COVERAGE=ON]
#   cmake --build build-test
#   ctest --test-dir build-test --output-on-failure
#
# Patterned after https://github.com/jwinarske/pw_dart/tree/main/test/native

option(J1939_BUILD_TESTING "Build j1939 C++ unit tests" OFF)
option(J1939_ENABLE_COVERAGE "Instrument for gcov/lcov coverage" OFF)

if(J1939_ENABLE_COVERAGE)
    if(NOT CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        message(WARNING "Coverage only supported on GCC/Clang — ignoring")
    else()
        add_compile_options(-O0 -g --coverage)
        add_link_options(--coverage)
    endif()
endif()

if(J1939_BUILD_TESTING)
    enable_testing()
    add_subdirectory(test/native)
endif()

# ── Summary ───────────────────────────────────────────────────────────────────

message(STATUS "")
message(STATUS "j1939 build configuration")
message(STATUS "  Build type   : ${CMAKE_BUILD_TYPE}")
message(STATUS "  Compiler     : ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
if(_DART_SDK_FOUND)
    message(STATUS "  Targets      : j1939_demo  j1939_plugin")
else()
    message(STATUS "  Targets      : j1939_demo")
endif()
message(STATUS "  ASIO source  : ${asio_SOURCE_DIR}")
if(_DART_SDK_FOUND)
    message(STATUS "  Dart SDK     : ${DART_SDK}")
endif()
if(J1939_BUILD_TESTING)
    message(STATUS "  C++ tests    : ON")
endif()
message(STATUS "")
