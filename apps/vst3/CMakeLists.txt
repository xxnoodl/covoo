cmake_minimum_required(VERSION 3.25)
project(covoo_vst3 VERSION 0.1.0 LANGUAGES C CXX)

enable_testing()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Core tests need no SDK, audio device, installation or network access.
find_package(Threads REQUIRED)
add_executable(covoo_source_test tests/source_test.cpp)
target_include_directories(covoo_source_test PRIVATE source)
target_link_libraries(covoo_source_test PRIVATE Threads::Threads)
if(MSVC)
    target_compile_options(covoo_source_test PRIVATE /W4 /WX)
else()
    target_compile_options(covoo_source_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME source_core COMMAND covoo_source_test)
set_tests_properties(source_core PROPERTIES TIMEOUT 30)

set(COVOO_VST3_SDK "" CACHE PATH "Pinned VST 3 SDK checkout; empty builds core tests only")
if(NOT COVOO_VST3_SDK)
    return()
endif()

# Never register, install or link into the host's plug-in search paths.
set(SMTG_CREATE_PLUGIN_LINK OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VSTGUI_SUPPORT OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VST3_HOSTING_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VST3_PLUGIN_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SMTG_DISABLE_CODE_SIGNING ON CACHE BOOL "" FORCE)
set(SMTG_RUN_VST_VALIDATOR ON CACHE BOOL "" FORCE)
add_subdirectory("${COVOO_VST3_SDK}" sdk)
list(APPEND CMAKE_MODULE_PATH "${COVOO_VST3_SDK}/cmake/modules")
include(SMTG_VST3_SDK)
set(SDK_ROOT "${COVOO_VST3_SDK}")

smtg_add_vst3plugin(covoo_source source/plugin.cpp source/plugin.h source/factory.cpp)
target_link_libraries(covoo_source PRIVATE sdk)
target_compile_features(covoo_source PRIVATE cxx_std_17)
target_include_directories(covoo_source PRIVATE "${COVOO_VST3_SDK}")
smtg_target_configure_version_file(covoo_source)
foreach(component IN ITEMS base cmake pluginterfaces public.sdk)
    smtg_target_add_plugin_resources(covoo_source
        RESOURCES "${COVOO_VST3_SDK}/${component}/LICENSE.txt"
        OUTPUT_SUBDIRECTORY "licenses/steinberg/${component}")
endforeach()
smtg_target_add_plugin_resources(covoo_source
    RESOURCES "${COVOO_VST3_SDK}/LICENSE.txt" OUTPUT_SUBDIRECTORY "licenses/steinberg/sdk")
smtg_target_add_plugin_resources(covoo_source
    RESOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../LICENSE" OUTPUT_SUBDIRECTORY "licenses/covoo")

# Exercise the real processor with synthetic PCM, without loading Live.
add_executable(covoo_processor_test tests/processor_test.cpp source/plugin.cpp
    "${COVOO_VST3_SDK}/public.sdk/source/common/memorystream.cpp")
target_link_libraries(covoo_processor_test PRIVATE sdk)
target_include_directories(covoo_processor_test PRIVATE source "${COVOO_VST3_SDK}")
add_test(NAME vst_processor COMMAND covoo_processor_test)
set_tests_properties(vst_processor PROPERTIES TIMEOUT 30)
if(WIN32)
    add_executable(covoo_bridge_host tests/bridge_host.cpp source/plugin.cpp
        "${COVOO_VST3_SDK}/public.sdk/source/common/memorystream.cpp")
    target_link_libraries(covoo_bridge_host PRIVATE sdk)
    target_include_directories(covoo_bridge_host PRIVATE source "${COVOO_VST3_SDK}")
    foreach(target IN ITEMS covoo_source covoo_processor_test covoo_bridge_host)
        target_sources(${target} PRIVATE source/bridge.cpp)
        target_link_libraries(${target} PRIVATE bcrypt advapi32 shell32 ole32)
    endforeach()
endif()
