cmake_minimum_required(VERSION 3.28)
project(tara-verilator LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
find_program(SAIL sail REQUIRED)
execute_process(COMMAND ${SAIL} --dir OUTPUT_VARIABLE SAIL_DIR
                OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
find_library(GMP gmp REQUIRED)
find_package(ZLIB REQUIRED)
find_package(CLI11 CONFIG REQUIRED)

set(HOST_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/../host.sail)
file(GLOB_RECURSE MODEL_SOURCES CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/../../model/*.sail)
add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/tara.c ${CMAKE_CURRENT_BINARY_DIR}/tara.h
  COMMAND ${SAIL} -c -O --c-no-main ${HOST_SOURCE} -o ${CMAKE_CURRENT_BINARY_DIR}/tara
  DEPENDS ${HOST_SOURCE} ${CMAKE_CURRENT_SOURCE_DIR}/../state.sail ${MODEL_SOURCES} ${SAIL}
  COMMENT "Generating initialization and text helpers with Sail"
  VERBATIM)
file(GLOB SAIL_RUNTIME ${SAIL_DIR}/lib/*.c)
add_library(host_model STATIC ${CMAKE_CURRENT_BINARY_DIR}/tara.c ${SAIL_RUNTIME})
target_compile_options(host_model PRIVATE -w)
target_include_directories(host_model SYSTEM PUBLIC ${SAIL_DIR}/lib ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(host_model PUBLIC ${GMP} ZLIB::ZLIB)
find_package(verilator REQUIRED)

set(STATE_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/../state.sail)
set(STEP_SOURCES ${STATE_SOURCE} ${MODEL_SOURCES})
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${STEP_SOURCES} ${SAIL})
set(SYSTEMVERILOG ${CMAKE_CURRENT_BINARY_DIR}/tara.sv)
set(SAIL_SV_COMMAND
    ${SAIL} --sv --sv-specialize 2 --sv-toplevel host_step --sv-comb
    --sv-no-unions --sv-never-pack-unions --sv-nomem --sv-no-write-flush --sv-output-dir
    ${CMAKE_CURRENT_BINARY_DIR} -o tara ${STATE_SOURCE})

# Verilator's CMake integration reads the SystemVerilog during configuration.
set(NEEDS_GENERATION FALSE)
foreach(SOURCE IN LISTS STEP_SOURCES SAIL)
  if(NOT EXISTS ${SYSTEMVERILOG} OR ${SOURCE} IS_NEWER_THAN ${SYSTEMVERILOG})
    set(NEEDS_GENERATION TRUE)
  endif()
endforeach()
if(NEEDS_GENERATION)
  execute_process(COMMAND ${SAIL_SV_COMMAND} COMMAND_ERROR_IS_FATAL ANY)
endif()
configure_file(${SAIL_DIR}/lib/sv/sail_modules.sv sail_modules.sv COPYONLY)
add_custom_command(
  OUTPUT ${SYSTEMVERILOG}
  COMMAND ${SAIL_SV_COMMAND}
  DEPENDS ${STEP_SOURCES} ${SAIL}
  COMMENT "Generating the step module's SystemVerilog with Sail"
  VERBATIM)
add_custom_target(generate DEPENDS ${SYSTEMVERILOG})

add_library(step_model STATIC)
verilate(
  step_model
  PREFIX Vtara_step
  TOP_MODULE tara_step
  DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/obj_dir
  SOURCES ${SYSTEMVERILOG}
  VERILATOR_ARGS --assert -Wno-fatal -I${CMAKE_CURRENT_BINARY_DIR})
target_compile_options(step_model PRIVATE -w)
target_include_directories(step_model SYSTEM PUBLIC ${CMAKE_CURRENT_BINARY_DIR}/obj_dir
                                                   ${VERILATOR_ROOT}/include)

function(tara_enable_cpp_warnings target)
  target_compile_options(
    ${target}
    PRIVATE -Werror -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion -Wformat=2
            -Wundef -Wcast-qual -Wcast-align -Wold-style-cast -Woverloaded-virtual -Wnon-virtual-dtor
            -Wnull-dereference -Wdouble-promotion -Wswitch-enum -Wfloat-equal -Wimplicit-fallthrough)
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_compile_options(${target} PRIVATE -Wlogical-op -Wduplicated-cond -Wduplicated-branches)
  endif()
endfunction()

add_library(machine STATIC src/machine.cc)
tara_enable_cpp_warnings(machine)
target_include_directories(machine PUBLIC src)
target_link_libraries(machine PRIVATE step_model host_model)

add_library(frontend STATIC src/inputs.cc src/options.cc src/run.cc src/keyboard.cc src/display.cc
                            src/terminal.cc src/play.cc)
tara_enable_cpp_warnings(frontend)
target_link_libraries(frontend PUBLIC machine PRIVATE CLI11::CLI11)
# CLI11 is a packaged dependency, so its headers are checked by its own build.
get_target_property(CLI11_INCLUDES CLI11::CLI11 INTERFACE_INCLUDE_DIRECTORIES)
target_include_directories(frontend SYSTEM PRIVATE ${CLI11_INCLUDES})

add_executable(tara-verilator src/main.cc)
tara_enable_cpp_warnings(tara-verilator)
target_link_libraries(tara-verilator PRIVATE frontend)

add_executable(state-test tests/state.cc)
tara_enable_cpp_warnings(state-test)
target_link_libraries(state-test PRIVATE frontend)

add_executable(keyboard-test tests/keyboard.cc)
tara_enable_cpp_warnings(keyboard-test)
target_link_libraries(keyboard-test PRIVATE frontend)
