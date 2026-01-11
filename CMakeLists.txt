cmake_minimum_required(VERSION 3.16)

project(Qt6InstallerGUI VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find Qt6 packages
find_package(Qt6 REQUIRED COMPONENTS Core Widgets)

# Enable automoc for Qt meta-object compiler
set(CMAKE_AUTOMOC ON)

# Create executable
add_executable(qt6-installer-gui
    main.cpp
)

# Link Qt6 libraries
target_link_libraries(qt6-installer-gui
    Qt6::Core
    Qt6::Widgets
)

# macOS-specific settings
if(APPLE)
    set_target_properties(qt6-installer-gui PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.qt6.installergui"
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
        MACOSX_BUNDLE_INFO_STRING "Qt6 Cross-Compilation Installer"
    )
endif()
