# The C emulator: the Sail model compiled to C, with tara-c's own sources around it.
cmake_minimum_required(VERSION 3.28)
project(tara-c LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
# For clang-tidy (just c lint) and editors.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_program(SAIL sail REQUIRED)
execute_process(
  COMMAND ${SAIL} --dir
  OUTPUT_VARIABLE SAIL_DIR
  OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
find_library(GMP gmp REQUIRED)
find_package(ZLIB REQUIRED)

# The model, generated from the emulators' host interface and everything it includes.
set(HOST ${CMAKE_CURRENT_SOURCE_DIR}/../host.sail)
file(GLOB_RECURSE MODEL_SOURCES CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/../../model/*.sail)
add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/tara.c ${CMAKE_CURRENT_BINARY_DIR}/tara.h
  COMMAND ${SAIL} -c -O --c-no-main ${HOST} -o ${CMAKE_CURRENT_BINARY_DIR}/tara
  DEPENDS ${HOST} ${CMAKE_CURRENT_SOURCE_DIR}/../state.sail ${MODEL_SOURCES}
  COMMENT "Generating the model's C with Sail"
  VERBATIM)

# The generated model and Sail's C runtime are not ours: their headers are system headers, and
# they compile without warnings.
file(GLOB SAIL_RUNTIME ${SAIL_DIR}/lib/*.c)
add_library(model STATIC ${CMAKE_CURRENT_BINARY_DIR}/tara.c ${SAIL_RUNTIME})
target_include_directories(model SYSTEM PUBLIC ${SAIL_DIR}/lib ${CMAKE_CURRENT_BINARY_DIR})
target_compile_options(model PRIVATE -w)
# Sail's runtime uses POSIX functions (getline, strnlen) without asking for them: GNU C.
set_target_properties(model PROPERTIES C_EXTENSIONS ON)
target_link_libraries(model PUBLIC ${GMP} ZLIB::ZLIB)

add_executable(
  tara-c
  src/batch.c
  src/clock.c
  src/disasm.c
  src/display.c
  src/image.c
  src/input.c
  src/interactive.c
  src/keys.c
  src/keyscript.c
  src/machine.c
  src/main.c
  src/number.c
  src/options.c
  src/report.c
  src/run.c
  src/terminal.c)
target_compile_definitions(tara-c PRIVATE _POSIX_C_SOURCE=200809L)
target_compile_options(
  tara-c
  PRIVATE -Werror
          -Wall
          -Wextra
          -Wpedantic
          -Wshadow
          -Wconversion
          -Wsign-conversion
          -Wformat=2
          -Wundef
          -Wcast-qual
          -Wcast-align
          -Wwrite-strings
          -Wstrict-prototypes
          -Wmissing-prototypes
          -Wmissing-declarations
          -Wold-style-definition
          -Wredundant-decls
          -Wnull-dereference
          -Wdouble-promotion
          -Wswitch-enum
          -Wvla
          -Wfloat-equal
          -Wimplicit-fallthrough
          -Wunused-macros)
if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
  target_compile_options(tara-c PRIVATE -Wjump-misses-init -Wlogical-op -Wduplicated-cond
                                        -Wduplicated-branches)
endif()
target_link_libraries(tara-c PRIVATE model)
