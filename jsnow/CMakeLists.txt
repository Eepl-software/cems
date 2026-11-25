cmake_minimum_required(VERSION 3.16)
project(jsnow LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

option(JSNOW_HW_GATHER "Use AVX2 vpgatherdd (fast unless the CPU has the Gather Data Sampling microcode mitigation)" ON)
option(JSNOW_NATIVE "Compile for the host CPU (-march=native) instead of plain AVX2+FMA" OFF)

add_executable(jsnow
  src/main.cpp
  src/engine.cpp
  src/texture.cpp
  src/shadow.cpp
  src/occlusion.cpp
  src/streaming.cpp
  src/scene.cpp
  src/raster.cpp
  src/post.cpp
  src/png.cpp)

if(JSNOW_HW_GATHER)
  target_compile_definitions(jsnow PRIVATE JSNOW_HW_GATHER=1)
endif()

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

# ---- Phase E: JSNOW as a Vulkan driver (ICD) ----
option(JSNOW_BUILD_ICD "Build the JSNOW Vulkan ICD (needs Vulkan headers + xcb)" ON)
find_path(VULKAN_ICD_HEADER vulkan/vk_icd.h)
find_library(XCB_LIB xcb)
if(JSNOW_BUILD_ICD AND VULKAN_ICD_HEADER AND XCB_LIB)
  add_library(jsnow_icd SHARED icd/icd.cpp icd/spirv.cpp)
  target_compile_options(jsnow_icd PRIVATE -O2 -fvisibility=hidden -Wall)
  target_link_libraries(jsnow_icd PRIVATE ${XCB_LIB} Threads::Threads)
  set_target_properties(jsnow_icd PROPERTIES PREFIX "lib")
  file(GENERATE OUTPUT ${CMAKE_BINARY_DIR}/jsnow_icd.json CONTENT
"{\n  \"file_format_version\": \"1.0.0\",\n  \"ICD\": {\n    \"library_path\": \"$<TARGET_FILE:jsnow_icd>\",\n    \"api_version\": \"1.0.0\"\n  }\n}\n")
endif()
