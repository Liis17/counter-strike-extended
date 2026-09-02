cmake_minimum_required(VERSION 3.21)

project(cse_mapcycle LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "The CSE server proxy currently targets the Windows dedicated server.")
endif()

if(CMAKE_SIZEOF_VOID_P GREATER 4)
    message(FATAL_ERROR "The CSE server proxy must be built as a 32-bit (x86) DLL.")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(YAPB_EXT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../cs16-client/3rdparty/yapb/ext")

add_library(cse_mapcycle SHARED mapcycle_proxy.cpp)

target_compile_definitions(cse_mapcycle PRIVATE NOMINMAX)
target_include_directories(cse_mapcycle PRIVATE
    "${YAPB_EXT_DIR}"
    "${YAPB_EXT_DIR}/crlib"
    "${YAPB_EXT_DIR}/linkage"
)

if(MSVC)
    set_property(TARGET cse_mapcycle PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

set_target_properties(cse_mapcycle PROPERTIES
    PREFIX ""
    OUTPUT_NAME "cse_mapcycle"
)

install(TARGETS cse_mapcycle
    RUNTIME DESTINATION cstrike/dlls
    LIBRARY DESTINATION cstrike/dlls
)
