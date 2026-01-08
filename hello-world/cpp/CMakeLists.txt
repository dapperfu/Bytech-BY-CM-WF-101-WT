cmake_minimum_required(VERSION 3.10)
project(HelloWorld LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)

set(CMAKE_C_FLAGS "-march=armv6 -mtune=arm1176jzf-s -mfloat-abi=softfp")
set(CMAKE_CXX_FLAGS "-march=armv6 -mtune=arm1176jzf-s -mfloat-abi=softfp")

add_executable(hello hello.cpp)

set_target_properties(hello PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/../bin"
)

