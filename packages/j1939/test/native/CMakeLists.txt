# GoogleTest unit tests for the j1939 C++ core.
#
# Built only when J1939_BUILD_TESTING=ON. Patterned after
# https://github.com/jwinarske/pw_dart/blob/main/test/native/CMakeLists.txt

cmake_minimum_required(VERSION 3.22)

# --- GoogleTest ---
include(FetchContent)
FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG        v1.15.2
  GIT_SHALLOW    TRUE
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

include(GoogleTest)

# --- Common settings ---
set(J1939_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../src)

# --- types_test: Id, Name, Dm1Fault encode/decode ---
add_executable(types_test types_test.cpp)
target_include_directories(types_test PRIVATE ${J1939_SRC_DIR})
target_link_libraries(types_test PRIVATE GTest::gtest_main)
gtest_discover_tests(types_test)
