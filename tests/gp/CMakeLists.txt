# gp - the GP effects image as wired for the APU's model (core/gp_image.c,
# BO-119): the routing table, polarity, the return path's timing and the LFE
# filter (bo3_gp_test), and a replay of a capture (bo3_gp_replay, by hand:
# tools/mix/gp_compare.py). No guest, no device, no game data.
#   cmake -S tests/gp -B <build> -DXBOXRECOMP_DIR=<toolkit> && ctest --test-dir <build>
cmake_minimum_required(VERSION 3.20)
if(NOT TARGET xbox_apu)
    project(bo3_gp_test C)
    set(CMAKE_C_STANDARD 11)
    if(NOT XBOXRECOMP_DIR)
        set(XBOXRECOMP_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../xboxrecomp")
    endif()
endif()
set(_gp_src ${CMAKE_CURRENT_LIST_DIR}/../../core/gp_image.c
            ${XBOXRECOMP_DIR}/src/apu/apu_gp.c
            ${XBOXRECOMP_DIR}/src/apu/apu_dsp56k.c)
add_executable(bo3_gp_replay replay.c ${_gp_src})
add_executable(bo3_gp_test test_main.c ${_gp_src})
foreach(_t bo3_gp_replay bo3_gp_test)
    target_include_directories(${_t} PRIVATE
        ${CMAKE_CURRENT_LIST_DIR}/../../core ${XBOXRECOMP_DIR}/src/apu)
    if(NOT WIN32)
        target_link_libraries(${_t} PRIVATE m)
    endif()
endforeach()
enable_testing()
add_test(NAME bo3_gp COMMAND bo3_gp_test)
