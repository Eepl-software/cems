cmake_minimum_required(VERSION 3.16)
project(jsnow LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

option(JSNOW_NATIVE "Compile for the host CPU (-march=native) instead of plain AVX2+FMA" OFF)

add_executable(jsnow
  src/main.cpp
  src/engine.cpp
  src/texture.cpp
  src/scene.cpp
  src/raster.cpp
  src/post.cpp
  src/png.cpp)

find_package(Threads REQUIRED)
target_link_libraries(jsnow PRIVATE Threads::Threads)

find_package(ZLIB QUIET)
if(ZLIB_FOUND)
  target_link_libraries(jsnow PRIVATE ZLIB::ZLIB)
  target_compile_definitions(jsnow PRIVATE JSNOW_HAVE_ZLIB=1)
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(jsnow PRIVATE -Wall -Wextra -O3 -fno-math-errno)
  if(JSNOW_NATIVE)
    target_compile_options(jsnow PRIVATE -march=native)
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
    target_compile_options(jsnow PRIVATE -mavx2 -mfma)
  endif()
elseif(MSVC)
  target_compile_options(jsnow PRIVATE /O2 /arch:AVX2)
endif()
