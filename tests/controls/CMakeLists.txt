# controls - the PS2 driving layout's table and its hand-over to the menus
# (core/controls.h, BO-106). Pure: no guest, no device, every host.
#   cmake --build <build> --target bo3_controls_test && ctest -R bo3_controls
# The toolkit's host map with it (input_map.c, pure): the whole chain from a
# host pad's buttons to what the title reads is checked, face layout included.
add_executable(bo3_controls_test test_main.c ${XBOXRECOMP_DIR}/src/input/input_map.c)
target_link_libraries(bo3_controls_test PRIVATE platform)
if(NOT WIN32)
    target_link_libraries(bo3_controls_test PRIVATE m)
endif()
target_include_directories(bo3_controls_test PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}/../../core
    ${XBOXRECOMP_DIR}/src
    ${XBOXRECOMP_DIR}/src/input)
enable_testing()
add_test(NAME bo3_controls COMMAND bo3_controls_test)
