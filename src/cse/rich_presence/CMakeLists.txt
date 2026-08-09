cmake_minimum_required(VERSION 3.20)
project(cse_steamrp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 32-bit (x86) is mandatory: steam_api.dll from HL/CS is x86 and xash3d.exe is x86.
# Configure with:  cmake -B build -A Win32
add_executable(cse_steamrp src/main.cpp)

if(MSVC)
    target_compile_options(cse_steamrp PRIVATE /W4 /permissive-)
endif()
