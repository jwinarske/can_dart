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
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(J1939_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../src)

# --- types_test: Id, Name, Dm1Fault encode/decode (pure, no socket) ---
add_executable(types_test types_test.cpp)
target_include_directories(types_test PRIVATE ${J1939_SRC_DIR})
target_link_libraries(types_test PRIVATE GTest::gtest_main)
gtest_discover_tests(types_test)

# --- network_test: AddressClaimer state machine (requires vcan0) ---
add_executable(network_test network_test.cpp)
target_link_libraries(network_test PRIVATE
    GTest::gtest_main
    $<TARGET_OBJECTS:j1939_objects>
    pthread
)
target_include_directories(network_test PRIVATE
    ${J1939_SRC_DIR}
    ${asio_SOURCE_DIR}/asio/include
)
target_compile_definitions(network_test PRIVATE
    ASIO_STANDALONE
    ASIO_NO_DEPRECATED
)
gtest_discover_tests(network_test)

# --- transport_test: BAM Receiver reassembly (requires vcan0) ---
add_executable(transport_test transport_test.cpp)
target_link_libraries(transport_test PRIVATE
    GTest::gtest_main
    $<TARGET_OBJECTS:j1939_objects>
    pthread
)
target_include_directories(transport_test PRIVATE
    ${J1939_SRC_DIR}
    ${asio_SOURCE_DIR}/asio/include
)
target_compile_definitions(transport_test PRIVATE
    ASIO_STANDALONE
    ASIO_NO_DEPRECATED
)
gtest_discover_tests(transport_test)
