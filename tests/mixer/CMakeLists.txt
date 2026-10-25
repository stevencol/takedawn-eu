# mixer - which sound goes to which bus (core/mixer.c, BO-114): the name
# rules, the wave table read from wave dictionaries made here, and a voice
# recognised by its buffer's bytes, its routing and who turned it on. No
# guest, no device, no game data.
#   cmake --build <build> --target bo3_mixer_test && ctest -R bo3_mixer
add_executable(bo3_mixer_test test_main.c ${CMAKE_CURRENT_LIST_DIR}/../../core/mixer.c)
target_link_libraries(bo3_mixer_test PRIVATE xbox_apu platform)
if(NOT WIN32)
    target_link_libraries(bo3_mixer_test PRIVATE m)
endif()
target_include_directories(bo3_mixer_test PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}/../../core
    ${XBOXRECOMP_DIR}/src/apu)
enable_testing()
add_test(NAME bo3_mixer COMMAND bo3_mixer_test)
