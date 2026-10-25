# start - the decisions of custom music at start (core/soundtrack_start.h,
# BO-230): which soundtrack to start on, when the switch is due, and what is
# the player's own choice. No guest, no settings, no device.
#   cmake -S tests/start -B <build> && cmake --build <build> && ctest --test-dir <build>
cmake_minimum_required(VERSION 3.20)
if(NOT TARGET burnout3)
    project(bo3_start_test C)
    set(CMAKE_C_STANDARD 11)
endif()
add_executable(bo3_start_test test_main.c)
target_include_directories(bo3_start_test PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../../core)
enable_testing()
add_test(NAME bo3_start COMMAND bo3_start_test)
