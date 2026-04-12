# GoogleTest unit tests for the can_engine C++ core.
#
# Built only when CAN_ENGINE_BUILD_TESTING=ON. Patterned after
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
set(CAN_ENGINE_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../src)

# --- bit_extract_test: extract_le, extract_be, normalize, filter states ---
add_executable(bit_extract_test bit_extract_test.cpp)
target_include_directories(bit_extract_test PRIVATE ${CAN_ENGINE_SRC_DIR})
target_link_libraries(bit_extract_test PRIVATE GTest::gtest_main)
gtest_discover_tests(bit_extract_test)
