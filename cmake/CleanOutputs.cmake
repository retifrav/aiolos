# Script mode helper for the clean-outputs target, so the glob runs when the
# target is invoked rather than at configure time. Removes the snapshots the
# test setups write into test_files/, which is what `make clean` did with
# `rm -f test_files/*dat`.

if(NOT DEFINED TEST_FILES_DIR)
    message(FATAL_ERROR "TEST_FILES_DIR must be set: cmake -DTEST_FILES_DIR=... -P CleanOutputs.cmake")
endif()

file(GLOB outputs "${TEST_FILES_DIR}/*.dat")
if(outputs)
    list(LENGTH outputs count)
    file(REMOVE ${outputs})
    message(STATUS "Removed ${count} .dat file(s) from ${TEST_FILES_DIR}")
else()
    message(STATUS "No .dat files in ${TEST_FILES_DIR}")
endif()
