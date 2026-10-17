cmake_minimum_required(VERSION 3.21)

project(pcn-calculator
    VERSION 0.1.0
    DESCRIPTION "Advanced calculator with modern style"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(pcn-calculator
    src/main.cpp
    src/calculatorengine.cpp
    src/calculatorengine.h
)

qt_add_qml_module(pcn-calculator
    URI PCNCalculator
    VERSION 1.0
    QML_FILES
        Main.qml
        CalcButton.qml
)

qt_add_resources(pcn-calculator "appicon"
    PREFIX "/"
    FILES icon.png
)

target_link_libraries(pcn-calculator PRIVATE Qt6::Quick)

# --- tests ---
qt_add_executable(test_engine
    tests/test_engine.cpp
    src/calculatorengine.cpp
    src/calculatorengine.h
)
target_include_directories(test_engine PRIVATE src)
target_link_libraries(test_engine PRIVATE Qt6::Core)

enable_testing()
add_test(NAME engine COMMAND test_engine)

include(GNUInstallDirs)

install(TARGETS pcn-calculator
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(FILES pcn-calculator.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
)
install(FILES icon.png
    DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/256x256/apps
    RENAME pcn-calculator.png
)
