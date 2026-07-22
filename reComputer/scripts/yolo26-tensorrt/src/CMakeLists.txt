cmake_minimum_required(VERSION 3.10)
project(yolo26_tensorrt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# CUDA
find_package(CUDAToolkit REQUIRED)

# TensorRT
find_path(NVINFER_INCLUDE_DIR NvInfer.h
    HINTS
        ${TENSORRT_ROOT}/include
        /usr/include/aarch64-linux-gnu
        /usr/include/x86_64-linux-gnu
        /usr/local/tensorrt/include
)
find_library(NVINFER_LIB nvinfer
    HINTS
        ${TENSORRT_ROOT}/lib
        /usr/lib/aarch64-linux-gnu
        /usr/lib/x86_64-linux-gnu
        /usr/local/tensorrt/lib
)
if (NOT NVINFER_INCLUDE_DIR OR NOT NVINFER_LIB)
    message(FATAL_ERROR "TensorRT not found. Set TENSORRT_ROOT or install JetPack TensorRT.")
endif()

# OpenCV
find_package(OpenCV QUIET)
if (NOT OpenCV_FOUND)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(OpenCV REQUIRED opencv4)
endif()

include_directories(
    ${CUDAToolkit_INCLUDE_DIRS}
    ${NVINFER_INCLUDE_DIR}
    ${OpenCV_INCLUDE_DIRS}
)

add_executable(yolo26_tensorrt main.cpp)

target_link_libraries(yolo26_tensorrt
    CUDA::cudart
    ${NVINFER_LIB}
    ${OpenCV_LIBS}
    pthread
)

if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(yolo26_tensorrt PRIVATE -O3 -Wall)
endif()
