cmake_minimum_required(VERSION 3.16)
project(can_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Asio — header-only, no Boost
include(FetchContent)

FetchContent_Declare(
  asio
  GIT_REPOSITORY https://github.com/chriskohlhoff/asio.git
  GIT_TAG        asio-1-30-2
  GIT_SHALLOW    TRUE
)

FetchContent_Declare(
  glaze
  GIT_REPOSITORY https://github.com/stephenberry/glaze.git
  GIT_TAG        v4.2.2
  GIT_SHALLOW    TRUE
)

FetchContent_MakeAvailable(asio glaze)

# Asio is header-only — create interface target
add_library(asio_headers INTERFACE)
target_include_directories(asio_headers INTERFACE
  ${asio_SOURCE_DIR}/asio/include
)
target_compile_definitions(asio_headers INTERFACE
  ASIO_STANDALONE
  ASIO_NO_DEPRECATED
)

# can_engine shared library
add_library(can_engine SHARED
  src/engine.cpp
  src/engine_api.cpp
)

target_include_directories(can_engine PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(can_engine PRIVATE
  asio_headers
  glaze::glaze
  pthread
)

# Install
install(TARGETS can_engine
  LIBRARY DESTINATION lib
)
