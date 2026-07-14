cmake_minimum_required(VERSION 3.20)
project(fltk-panel VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# --- Find dependencies ---
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(CAIRO REQUIRED cairo)
pkg_check_modules(PANGO REQUIRED pango pangocairo)

# --- Find wayland-scanner ---
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
message(STATUS "Found wayland-scanner: ${WAYLAND_SCANNER}")

# --- Generate layer-shell protocol code ---
set(PROTO_DIR ${CMAKE_SOURCE_DIR}/protocols)
set(PROTO_GEN_DIR ${CMAKE_BINARY_DIR}/protocol-gen)
file(MAKE_DIRECTORY ${PROTO_GEN_DIR})

set(LAYER_SHELL_XML ${PROTO_DIR}/wlr-layer-shell-unstable-v1.xml)
set(LAYER_SHELL_H ${PROTO_GEN_DIR}/wlr-layer-shell-unstable-v1-client.h)
set(LAYER_SHELL_C ${PROTO_GEN_DIR}/wlr-layer-shell-unstable-v1-client.c)

add_custom_command(
    OUTPUT ${LAYER_SHELL_H}
    COMMAND ${WAYLAND_SCANNER} client-header ${LAYER_SHELL_XML} ${LAYER_SHELL_H}
    DEPENDS ${LAYER_SHELL_XML}
    COMMENT "Generating layer-shell client header"
)
add_custom_command(
    OUTPUT ${LAYER_SHELL_C}
    COMMAND ${WAYLAND_SCANNER} private-code ${LAYER_SHELL_XML} ${LAYER_SHELL_C}
    DEPENDS ${LAYER_SHELL_XML}
    COMMENT "Generating layer-shell client code"
)

set(FTL_XML ${PROTO_DIR}/wlr-foreign-toplevel-management-unstable-v1.xml)
set(FTL_H ${PROTO_GEN_DIR}/wlr-foreign-toplevel-management-unstable-v1-client.h)
set(FTL_C ${PROTO_GEN_DIR}/wlr-foreign-toplevel-management-unstable-v1-client.c)

add_custom_command(
    OUTPUT ${FTL_H}
    COMMAND ${WAYLAND_SCANNER} client-header ${FTL_XML} ${FTL_H}
    DEPENDS ${FTL_XML}
    COMMENT "Generating foreign-toplevel client header"
)
add_custom_command(
    OUTPUT ${FTL_C}
    COMMAND ${WAYLAND_SCANNER} private-code ${FTL_XML} ${FTL_C}
    DEPENDS ${FTL_XML}
    COMMENT "Generating foreign-toplevel client code"
)

# --- Build FLTK from source (the copy in ../sources/fltk) ---
set(FLTK_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(FLTK_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(FLTK_BUILD_FLUID OFF CACHE BOOL "" FORCE)
set(FLTK_BUILD_FLTK_OPTIONS OFF CACHE BOOL "" FORCE)
set(FLTK_OPTION_CAIRO_EXT ON CACHE BOOL "" FORCE)
set(FLTK_GRAPHICS_CAIRO ON CACHE BOOL "" FORCE)
set(FLTK_BACKEND_X11 OFF CACHE BOOL "" FORCE)
set(FLTK_BACKEND_WAYLAND ON CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_SOURCE_DIR}/../sources/fltk ${CMAKE_BINARY_DIR}/fltk EXCLUDE_FROM_ALL)

# --- Main executable ---
add_executable(fltk-panel
    src/main.cpp
    src/wayland_panel.cpp
    src/panel_widgets.cpp
    src/system_info.cpp
    ${LAYER_SHELL_C}
    ${LAYER_SHELL_H}
    ${FTL_C}
    ${FTL_H}
)

target_include_directories(fltk-panel PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${PROTO_GEN_DIR}
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
    ${CAIRO_INCLUDE_DIRS}
    ${PANGO_INCLUDE_DIRS}
    ${CMAKE_SOURCE_DIR}/../sources/fltk   # FLTK source headers
    ${CMAKE_BINARY_DIR}/fltk      # FLTK generated config headers
)

target_link_libraries(fltk-panel PRIVATE
    fltk           # FLTK static lib (built from source)
    ${WAYLAND_CLIENT_LIBRARIES}
    ${CAIRO_LIBRARIES}
    ${PANGO_LIBRARIES}
    rt             # for shm_open
)

target_compile_definitions(fltk-panel PRIVATE
    _POSIX_C_SOURCE=200809L
)

# --- Install ---
install(TARGETS fltk-panel DESTINATION bin)

# --- Tests ---
include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/03597a01ee50ed33e9dfd640b249b4be3799d395.zip
)
# For Windows: Prevent overriding the parent project's compiler/linker settings
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

enable_testing()

add_executable(fltk-panel-tests
    tests/system_info_test.cpp
    src/system_info.cpp
)
target_include_directories(fltk-panel-tests PRIVATE src)
target_link_libraries(fltk-panel-tests
    GTest::gtest_main
)

include(GoogleTest)
gtest_discover_tests(fltk-panel-tests)
