# AIOLOS - 1-D multi-species radiation hydrodynamics
#
# Out-of-source build only. All artifacts land in the binary directory.
#
# Translation table from the old makefile:
#
#     make PROBLEM=my_problem        -> cmake -S . -B build -DPROBLEM=my_problem
#     make NUM_SPECIES=4             -> cmake -S . -B build -DNUM_SPECIES=4
#     make SYSTEM=clang              -> cmake -S . -B build -DCMAKE_CXX_COMPILER=clang++
#     make SYSTEM=intel              -> cmake -S . -B build -DCMAKE_CXX_COMPILER=icpx
#     make tests                     -> cmake --build build --target run-tests
#     make clean                     -> rm -rf build   (plus target clean-outputs for *.dat)
#
# The compiler cannot be changed in an existing build tree; configure a fresh
# one (or delete build/) when switching.
#
# Unlike the makefile, this build tracks header dependencies and re-compiles
# when NUM_SPECIES changes, so no manual clean is needed in either case.

cmake_minimum_required(VERSION 3.28)

project(aiolos LANGUAGES CXX)

set(REQUIRED_CPP_STANDARD 17 CACHE STRING "Required C++ standard")
if(DEFINED CMAKE_CXX_STANDARD)
    if(CMAKE_CXX_STANDARD LESS ${REQUIRED_CPP_STANDARD})
        message(FATAL_ERROR "This project requires at least C++${REQUIRED_CPP_STANDARD}")
    endif()
else()
    set(CMAKE_CXX_STANDARD ${REQUIRED_CPP_STANDARD})
endif()
set(CMAKE_CXX_STANDARD_REQUIRED YES)
if(NOT DEFINED CMAKE_CXX_EXTENSIONS)
    set(CMAKE_CXX_EXTENSIONS NO)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS YES)

set(PROBLEM
    "default"
    CACHE STRING
    "Problem setup to compile: problems/<PROBLEM>.cpp"
)
set(NUM_SPECIES
    "Eigen::Dynamic"
    CACHE STRING
    "Species count fixed at compile time; Eigen::Dynamic for a flexible build"
)

option(AIOLOS_NATIVE_ARCH "Optimise for the build host (-march=native / -xHost)"               1)
option(AIOLOS_LTO         "Link-time optimisation (-flto / -ipo)"                              0)
option(AIOLOS_BUILD_TESTS "Build the tests binary and register the test suite"                 1)
option(AIOLOS_TEST_PLOTS  "Pass -p to the Python checkers that can plot (requires matplotlib)" 1)

find_package(Eigen3 CONFIG REQUIRED)

# GSL, for <gsl/gsl_sf_lambert.h> included unconditionally by aiolos.h. Every call site
# (the analytic wind solution in helpers.cpp) is currently commented out, so in practice
# only the headers are needed - but the include makes GSL a hard compile-time requirement
find_package(GSL REQUIRED)

# aiolos.h provides inline fallbacks when _OPENMP is undefined, but the
# makefile's default build always enabled it, so it is required here as well
find_package(OpenMP REQUIRED COMPONENTS CXX)

# globbed to preserve the makefile's $(wildcard *.cpp) behaviour: a new
# root-level .cpp is picked up automatically. CONFIGURE_DEPENDS re-globs at
# build time, so a new file does not need a manual re-configure.
file(GLOB AIOLOS_CORE_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.cpp")
list(REMOVE_ITEM AIOLOS_CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/main.cpp")

if(NOT AIOLOS_CORE_SOURCES)
    message(FATAL_ERROR "No sources found in ${CMAKE_CURRENT_SOURCE_DIR}")
endif()

set(AIOLOS_PROBLEM_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/problems/${PROBLEM}.cpp")
if(NOT EXISTS "${AIOLOS_PROBLEM_SOURCE}")
    file(GLOB available_problems RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}/problems"
         "${CMAKE_CURRENT_SOURCE_DIR}/problems/*.cpp")
    list(TRANSFORM available_problems REPLACE "\\.cpp$" "")
    list(JOIN available_problems ", " available_problems)
    message(FATAL_ERROR
        "PROBLEM=${PROBLEM} not found: ${AIOLOS_PROBLEM_SOURCE}\n"
        "Available problem setups: ${available_problems}")
endif()

# Core objects: everything except the two competing main() definitions, shared
# by the aiolos binary and the test driver (the makefile achieved this by
# substituting main.o for test_files/main.o).
#
# OBJECT rather than STATIC or an unqualified add_library(): nothing consumes
# this as a library - there are no install/export rules - it exists only so
# these translation units are not compiled once per executable. That also keeps
# BUILD_SHARED_LIBS from turning it into a shared object, which this code is
# not set up for (no visibility control, no SOVERSION, and a runtime dependency
# that build-tree RPATH would hide until the binary is copied elsewhere).

add_library(aiolos_core OBJECT ${AIOLOS_CORE_SOURCES} "${AIOLOS_PROBLEM_SOURCE}")

# PUBLIC throughout: both executables include aiolos.h and so need the same
# include paths, definitions and libraries.
target_include_directories(aiolos_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(aiolos_core PUBLIC NUM_SPECIES=${NUM_SPECIES})
target_compile_features(aiolos_core PUBLIC "cxx_std_${REQUIRED_CPP_STANDARD}")

target_link_libraries(aiolos_core PUBLIC
    Eigen3::Eigen
    GSL::gsl
    GSL::gslcblas
    OpenMP::OpenMP_CXX
)
if(UNIX)
    target_link_libraries(aiolos_core PUBLIC m)
endif()

target_compile_options(aiolos_core
    PUBLIC
        $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang,Intel,IntelLLVM>:-Wall;-Wextra>
)

# Host-specific tuning: -xHost for the Intel compilers, -march=native
# elsewhere, and only when the compiler actually accepts it (it is rejected by,
# for example, Apple clang on Apple silicon).
if(AIOLOS_NATIVE_ARCH)
    include(CheckCXXCompilerFlag)
    if(CMAKE_CXX_COMPILER_ID MATCHES "^Intel")
        set(AIOLOS_ARCH_FLAG -xHost)
    else()
        set(AIOLOS_ARCH_FLAG -march=native)
    endif()
    check_cxx_compiler_flag("${AIOLOS_ARCH_FLAG}" AIOLOS_HAVE_ARCH_FLAG)
    if(AIOLOS_HAVE_ARCH_FLAG)
        target_compile_options(aiolos_core PUBLIC "${AIOLOS_ARCH_FLAG}")
    else()
        message(STATUS "AIOLOS: ${CMAKE_CXX_COMPILER_ID} rejects ${AIOLOS_ARCH_FLAG}, "
                       "building without host-specific tuning")
    endif()
endif()

# portable replacement for the makefile's -flto (clang) / -ipo (intel)
if(AIOLOS_LTO)
    include(CheckIPOSupported)
    check_ipo_supported(RESULT AIOLOS_IPO_SUPPORTED OUTPUT AIOLOS_IPO_ERROR)
    if(AIOLOS_IPO_SUPPORTED)
        set_property(TARGET aiolos_core PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
    else()
        message(WARNING "AIOLOS_LTO requested but unsupported: ${AIOLOS_IPO_ERROR}")
    endif()
endif()

#
# executables
#

add_executable(aiolos main.cpp)
target_link_libraries(aiolos PRIVATE aiolos_core)
if(AIOLOS_LTO AND AIOLOS_IPO_SUPPORTED)
    set_property(TARGET aiolos PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()

include(GNUInstallDirs)

set(TARGETS_TO_INSTALL "aiolos")

#
# tests
#
# test_files/main.cpp runs ~25 parameter setups in-process. It takes no
# arguments at all: the *.par setups are hardcoded as "test_files/..." and the
# opacity tables as "inputdata/...", both relative to the current working
# directory. Its WORKING_DIRECTORY below is therefore load-bearing and has to
# be the repository root - without it every setup fails to find its input data.
#
# The Python checkers need a working directory too, one level further in: they
# import load_aiolos and read output_*.dat from the current directory.
#

if(AIOLOS_BUILD_TESTS)
    # Target name kept distinct from the run-tests driver below; the binary is
    # still ./build/tests, as with the makefile.
    add_executable(aiolos_tests test_files/main.cpp)
    set_target_properties(aiolos_tests PROPERTIES OUTPUT_NAME tests)
    target_link_libraries(aiolos_tests PRIVATE aiolos_core)
    if(AIOLOS_LTO AND AIOLOS_IPO_SUPPORTED)
        set_property(TARGET aiolos_tests PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
    endif()

    enable_testing()

    # Produces the output_*.dat snapshots the Python checkers read. Its exit
    # code is the number of crashed setups.
    add_test(NAME aiolos.setups
             COMMAND aiolos_tests
             WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
    set_tests_properties(aiolos.setups PROPERTIES
        FIXTURES_SETUP aiolos_outputs
        TIMEOUT 3600)

    # Python checkers, in the order the makefile ran them. Each entry is
    # <script>[|<arg>...]; a | separator is used because a nested ;-list would
    # flatten into the outer list.
    set(AIOLOS_CHECKERS
        "test_shock_tube.py|-p"
        "test_steady_state.py"
        "test_drag.py"
        "test_dustywave.py|-p"
        "test_dustyshock.py|-p"
        "test_conservation.py"
        "test_irradiation.py|-p")
    # test_coll_heating.py takes no -p flag.
    list(APPEND AIOLOS_CHECKERS "test_coll_heating.py")

    find_package(Python3 COMPONENTS Interpreter REQUIRED)
    message(STATUS "Python found: ${Python3_FOUND}")
    message(STATUS "Python path: ${Python3_EXECUTABLE}")
    if(NOT Python3_Interpreter_FOUND)
        message(STATUS "AIOLOS: no python3 interpreter found, the numerical "
                       "checkers are not registered (aiolos.setups still runs)")
    endif()

    foreach(checker IN LISTS AIOLOS_CHECKERS)
        string(REPLACE "|" ";" checker "${checker}")
        list(POP_FRONT checker script)
        if(NOT AIOLOS_TEST_PLOTS)
            set(checker "")
        endif()
        string(REGEX REPLACE "^test_(.*)\\.py$" "\\1" name "${script}")

        if(Python3_Interpreter_FOUND)
            add_test(NAME check.${name}
                     COMMAND "${Python3_EXECUTABLE}" "${script}" ${checker}
                     WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/test_files")
            # The checkers print "passed"/"failed" and always exit 0, so
            # without this a numerical regression would go unnoticed - as it
            # did under `make tests`.
            set_tests_properties(check.${name} PROPERTIES
                FIXTURES_REQUIRED aiolos_outputs
                FAIL_REGULAR_EXPRESSION "failed"
                TIMEOUT 600)
        endif()
    endforeach()

    # One-command equivalent of `make tests`: build the driver, then run the
    # simulations and every checker.
    # Multi-config generators need ctest told which configuration to run;
    # single-config ones reject -C, hence the plain if() rather than a
    # generator expression over CMAKE_CONFIGURATION_TYPES (a multi-item list
    # would not survive being interpolated into one).
    set(AIOLOS_CTEST_CONFIG "")
    if(CMAKE_CONFIGURATION_TYPES)
        set(AIOLOS_CTEST_CONFIG -C $<CONFIG>)
    endif()
    add_custom_target(run-tests
        COMMAND "${CMAKE_CTEST_COMMAND}" --test-dir "${CMAKE_BINARY_DIR}"
                --output-on-failure ${AIOLOS_CTEST_CONFIG}
        COMMENT "Running the AIOLOS test setups and numerical checkers"
        USES_TERMINAL
        VERBATIM)
    add_dependencies(run-tests aiolos_tests)

    list(APPEND TARGETS_TO_INSTALL "aiolos_tests")
endif()

install(TARGETS ${TARGETS_TO_INSTALL})

#
# Cleaning
#
# Object files and binaries all live in the build directory, so `rm -rf build`
# covers what `make clean` removed there. The snapshots the test setups write
# into test_files/ are outside the build tree and need their own target; the
# glob has to happen when the target runs, hence the script-mode helper.
#

add_custom_target(clean-outputs
    COMMAND "${CMAKE_COMMAND}"
            "-DTEST_FILES_DIR=${CMAKE_SOURCE_DIR}/test_files"
            -P "${CMAKE_SOURCE_DIR}/cmake/CleanOutputs.cmake"
    COMMENT "Removing test_files/*.dat"
    VERBATIM)

#
# Configuration summary
#

message(STATUS "AIOLOS: problem      problems/${PROBLEM}.cpp")
message(STATUS "AIOLOS: NUM_SPECIES  ${NUM_SPECIES}")
message(STATUS "AIOLOS: build type   ${CMAKE_BUILD_TYPE}")
message(STATUS "AIOLOS: compiler     ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "AIOLOS: binaries in  ${CMAKE_BINARY_DIR}")
