# script-mode helper for the clean-outputs target, so the globs run
# when the target is invoked. Removes what the test setups
# and the Python checkers leave in `./test_files/`: snapshots and plots
#
# the `./test_files/plots/` directory itself is not removed: `test_dustywave.py`
# and `test_dustyshock.py` do `savefig` straight into it without a `makedirs()`,
# so removing it makes those two checkers fail unless one of the checkers that does
# create it runs first

if(NOT DEFINED TEST_FILES_DIR)
    message(FATAL_ERROR "TEST_FILES_DIR must be set: cmake -DTEST_FILES_DIR=... -P CleanOutputs.cmake")
endif()

function(remove_matching what pattern)
    file(GLOB victims "${pattern}")
    if(victims)
        list(LENGTH victims count)
        file(REMOVE ${victims})
        message(STATUS "Removed ${count} ${what} from ${TEST_FILES_DIR}")
    else()
        message(STATUS "No ${what} in ${TEST_FILES_DIR}")
    endif()
endfunction()

remove_matching(".dat file(s)" "${TEST_FILES_DIR}/*.dat")
remove_matching("plot(s)" "${TEST_FILES_DIR}/plots/*.png")
