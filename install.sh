#!/bin/bash
set -e  # Exit on error

# Qt6 Cross-Compilation Setup Script for macOS Sequoia
# Builds Qt6 natively for macOS and cross-compiles for Windows ARM64
# Author: Pedro
# Date: 2025-01-10
# Platform: macOS Sequoia 15.2

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
QT_VERSION="6.8"
LLVM_MINGW_VERSION="20231128"
HOME_DIR="$HOME"
QT_SRC_DIR="$HOME_DIR/qt6-src"
BUILD_HOST_DIR="$HOME_DIR/qt6-build-host-macos"
BUILD_WIN_DIR="$HOME_DIR/qt6-build-winarm64"
INSTALL_HOST_DIR="$HOME_DIR/qt6-host-macos"
INSTALL_WIN_DIR="$HOME_DIR/qt6-winarm64"
LLVM_MINGW_DIR="$HOME_DIR/llvm-mingw"
PARALLEL_JOBS=4

# Get BUILD_QML from environment or default to 'n'
BUILD_QML="${BUILD_QML:-n}"

# Verbose mode - always on
VERBOSE=1

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_verbose() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "${NC}$1${NC}"
    fi
}

# Check if component is installed
is_installed() {
    local component=$1
    case $component in
        "llvm-mingw")
            [ -f "$LLVM_MINGW_DIR/bin/aarch64-w64-mingw32-clang++" ]
            ;;
        "toolchain")
            [ -f "$HOME_DIR/llvm-mingw-toolchain.cmake" ]
            ;;
        "qt6-source")
            [ -d "$QT_SRC_DIR/qtbase" ]
            ;;
        "qt6-host")
            [ -f "$INSTALL_HOST_DIR/libexec/moc" ]
            ;;
        "qt6-windows-base")
            [ -f "$INSTALL_WIN_DIR/lib/cmake/Qt6/Qt6Config.cmake" ]
            ;;
        "qt6-host-qml")
            [ -f "$INSTALL_HOST_DIR/libexec/qmlcachegen" ]
            ;;
        "qt6-windows-qml")
            [ -f "$INSTALL_WIN_DIR/lib/cmake/Qt6Qml/Qt6QmlConfig.cmake" ]
            ;;
        "test-app")
            [ -f "$HOME_DIR/qt6-hello-test/main.cpp" ]
            ;;
        *)
            return 1
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    echo_info "Checking prerequisites..."
    
    if ! command -v cmake &> /dev/null; then
        echo_error "CMake not found. Install with: brew install cmake"
        exit 1
    fi
    echo_verbose "  ✓ CMake found: $(cmake --version | head -n1)"
    
    if ! command -v git &> /dev/null; then
        echo_error "Git not found. Install Xcode Command Line Tools"
        exit 1
    fi
    echo_verbose "  ✓ Git found: $(git --version)"
    
    if command -v ninja &> /dev/null; then
        echo_verbose "  ✓ Ninja found: $(ninja --version)"
        USE_NINJA=1
    else
        echo_verbose "  ℹ Ninja not found, using make (slower)"
        USE_NINJA=0
    fi
    
    echo_success "Prerequisites check passed"
}

# Download and setup llvm-mingw
setup_llvm_mingw() {
    echo_info "Setting up llvm-mingw..."
    
    if is_installed "llvm-mingw"; then
        echo_success "llvm-mingw already installed at $LLVM_MINGW_DIR"
        echo_verbose "  Compiler: $LLVM_MINGW_DIR/bin/aarch64-w64-mingw32-clang++"
        return
    fi
    
    cd "$HOME_DIR"
    LLVM_MINGW_ARCHIVE="llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-macos-universal.tar.xz"
    
    if [ ! -f "$LLVM_MINGW_ARCHIVE" ]; then
        echo_info "Downloading llvm-mingw..."
        echo_verbose "  URL: https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${LLVM_MINGW_ARCHIVE}"
        curl -L -O "https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${LLVM_MINGW_ARCHIVE}"
    else
        echo_verbose "  Using cached archive: $LLVM_MINGW_ARCHIVE"
    fi
    
    echo_info "Extracting llvm-mingw..."
    tar xf "$LLVM_MINGW_ARCHIVE"
    mv "llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-macos-universal" llvm-mingw
    
    echo_success "llvm-mingw installed to $LLVM_MINGW_DIR"
    echo_verbose "  Testing compiler..."
    $LLVM_MINGW_DIR/bin/aarch64-w64-mingw32-clang++ --version | head -n1
}

# Create CMake toolchain file
create_toolchain_file() {
    echo_info "Creating CMake toolchain file..."
    
    if is_installed "toolchain"; then
        echo_success "Toolchain file already exists at $HOME_DIR/llvm-mingw-toolchain.cmake"
        return
    fi
    
    cat > "$HOME_DIR/llvm-mingw-toolchain.cmake" << 'EOF'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ARM64)

# Get the home directory
file(TO_CMAKE_PATH "$ENV{HOME}" HOME_DIR)

set(CMAKE_C_COMPILER ${HOME_DIR}/llvm-mingw/bin/aarch64-w64-mingw32-clang)
set(CMAKE_CXX_COMPILER ${HOME_DIR}/llvm-mingw/bin/aarch64-w64-mingw32-clang++)
set(CMAKE_RC_COMPILER ${HOME_DIR}/llvm-mingw/bin/aarch64-w64-mingw32-windres)

set(CMAKE_FIND_ROOT_PATH ${HOME_DIR}/llvm-mingw/aarch64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
    
    echo_success "Toolchain file created at $HOME_DIR/llvm-mingw-toolchain.cmake"
    echo_verbose "$(cat $HOME_DIR/llvm-mingw-toolchain.cmake)"
}

# Download Qt6 source
download_qt6_source() {
    echo_info "Downloading Qt6 source code..."
    
    if is_installed "qt6-source"; then
        echo_success "Qt6 source already exists at $QT_SRC_DIR"
        echo_verbose "  Qt version branch: $(cd $QT_SRC_DIR && git branch --show-current)"
        return
    fi
    
    cd "$HOME_DIR"
    echo_info "Cloning Qt6 repository (this may take a while)..."
    echo_verbose "  Repository: https://code.qt.io/qt/qt5.git"
    echo_verbose "  Branch: $QT_VERSION"
    
    git clone https://code.qt.io/qt/qt5.git qt6-src
    cd qt6-src
    git checkout "$QT_VERSION"
    
    echo_info "Initializing Qt6 submodules..."
    if [[ $BUILD_QML =~ ^[Yy]$ ]]; then
        echo_verbose "  Modules: qtbase, qtdeclarative, qtshadertools, qtsvg, qtimageformats"
        perl init-repository --module-subset=qtbase,qtdeclarative,qtshadertools,qtsvg,qtimageformats -f
    else
        echo_verbose "  Modules: qtbase, qtsvg, qtimageformats"
        perl init-repository --module-subset=qtbase,qtsvg,qtimageformats -f
    fi
    
    echo_success "Qt6 source downloaded to $QT_SRC_DIR"
}

# Build Qt6 host tools (macOS)
build_qt6_host() {
    echo_info "Building Qt6 host tools for macOS..."
    
    if is_installed "qt6-host"; then
        echo_success "Qt6 host tools already built at $INSTALL_HOST_DIR"
        echo_verbose "  moc version: $($INSTALL_HOST_DIR/libexec/moc -v 2>&1 | head -n1)"
        return
    fi
    
    mkdir -p "$BUILD_HOST_DIR"
    cd "$BUILD_HOST_DIR"
    
    echo_info "Configuring Qt6 host build..."
    echo_verbose "  Source: $QT_SRC_DIR"
    echo_verbose "  Install prefix: $INSTALL_HOST_DIR"
    echo_verbose "  Build type: Release"
    echo_verbose "  Parallel jobs: $PARALLEL_JOBS"
    
    if [ "$USE_NINJA" -eq 1 ]; then
        cmake "$QT_SRC_DIR" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$INSTALL_HOST_DIR" \
            -DQT_BUILD_EXAMPLES=OFF \
            -DQT_BUILD_TESTS=OFF \
            -DQT_FORCE_BUILD_TOOLS=ON \
            -GNinja
    else
        cmake "$QT_SRC_DIR" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$INSTALL_HOST_DIR" \
            -DQT_BUILD_EXAMPLES=OFF \
            -DQT_BUILD_TESTS=OFF \
            -DQT_FORCE_BUILD_TOOLS=ON
    fi
    
    echo_info "Building Qt6 host (this will take 1-2 hours)..."
    echo_verbose "  Command: cmake --build . --parallel $PARALLEL_JOBS"
    cmake --build . --parallel "$PARALLEL_JOBS" 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_info "Installing Qt6 host..."
    cmake --install . 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    # Verify installation
    if [ -f "$INSTALL_HOST_DIR/libexec/moc" ]; then
        echo_success "Qt6 host tools built successfully!"
        echo_info "moc location: $INSTALL_HOST_DIR/libexec/moc"
        echo_verbose "$($INSTALL_HOST_DIR/libexec/moc -v 2>&1)"
    else
        echo_error "Qt6 host build failed - moc not found"
        exit 1
    fi
}

# Build Qt6 base for Windows
build_qt6_windows_base() {
    echo_info "Building Qt6 base (qtbase) for Windows ARM64..."
    
    if is_installed "qt6-windows-base"; then
        echo_success "Qt6 Windows base already built at $INSTALL_WIN_DIR"
        return
    fi
    
    mkdir -p "$BUILD_WIN_DIR"
    cd "$BUILD_WIN_DIR"
    
    echo_info "Configuring Qt6 Windows build..."
    echo_verbose "  Source: $QT_SRC_DIR/qtbase"
    echo_verbose "  Toolchain: $HOME_DIR/llvm-mingw-toolchain.cmake"
    echo_verbose "  Host path: $INSTALL_HOST_DIR"
    echo_verbose "  Install prefix: $INSTALL_WIN_DIR"
    
    cmake "$QT_SRC_DIR/qtbase" \
        -DCMAKE_TOOLCHAIN_FILE="$HOME_DIR/llvm-mingw-toolchain.cmake" \
        -DQT_HOST_PATH="$INSTALL_HOST_DIR" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_WIN_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_info "Building Qt6 Windows base (this will take 30-60 minutes)..."
    cmake --build . --parallel "$PARALLEL_JOBS" 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_info "Installing Qt6 Windows base..."
    cmake --install . 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    # Verify installation
    if [ -f "$INSTALL_WIN_DIR/lib/cmake/Qt6/Qt6Config.cmake" ]; then
        echo_success "Qt6 Windows base built successfully!"
        echo_verbose "  Config file: $INSTALL_WIN_DIR/lib/cmake/Qt6/Qt6Config.cmake"
    else
        echo_error "Qt6 Windows base build failed"
        exit 1
    fi
}

# Build Qt6 QML modules for Windows (optional)
build_qt6_windows_qml() {
    echo_info "Building Qt6 QML modules for Windows ARM64..."
    
    # Check if host QML is installed
    if ! is_installed "qt6-host-qml"; then
        # Build qtshadertools for host first
        echo_info "Building qtshadertools for host..."
        mkdir -p "$HOME_DIR/qt6-build-host-macos-shadertools"
        cd "$HOME_DIR/qt6-build-host-macos-shadertools"
        
        echo_verbose "  Configuring qtshadertools (host)..."
        cmake "$QT_SRC_DIR/qtshadertools" \
            -DCMAKE_PREFIX_PATH="$INSTALL_HOST_DIR" \
            -DCMAKE_INSTALL_PREFIX="$INSTALL_HOST_DIR" \
            -DCMAKE_BUILD_TYPE=Release \
            -DQT_BUILD_EXAMPLES=OFF \
            -DQT_BUILD_TESTS=OFF 2>&1 | while IFS= read -r line; do
            echo_verbose "$line"
        done
        
        echo_verbose "  Building qtshadertools (host)..."
        cmake --build . --parallel "$PARALLEL_JOBS" 2>&1 | while IFS= read -r line; do
            echo_verbose "$line"
        done
        cmake --install . 2>&1 | while IFS= read -r line; do
            echo_verbose "$line"
        done
        
        # Build qtdeclarative for host
        echo_info "Building qtdeclarative for host..."
        mkdir -p "$HOME_DIR/qt6-build-host-macos-declarative"
        cd "$HOME_DIR/qt6-build-host-macos-declarative"
        
        echo_verbose "  Configuring qtdeclarative (host)..."
        cmake "$QT_SRC_DIR/qtdeclarative" \
            -DCMAKE_PREFIX_PATH="$INSTALL_HOST_DIR" \
            -DCMAKE_INSTALL_PREFIX="$INSTALL_HOST_DIR" \
            -DCMAKE_BUILD_TYPE=Release \
            -DQT_BUILD_EXAMPLES=OFF \
            -DQT_BUILD_TESTS=OFF \
            -DQT_FORCE_BUILD_TOOLS=ON 2>&1 | while IFS= read -r line; do
            echo_verbose "$line"
        done
        
        echo_verbose "  Building qtdeclarative (host)..."
        cmake --build . --parallel "$PARALLEL_JOBS" 2>&1 | while IFS= read -r line; do
            echo_verbose "$line"
        done
        cmake --install . 2>&1 | while IFS= read -r line; do
            echo_verbose "$line"
        done
        
        echo_success "Qt6 host QML tools installed"
    else
        echo_success "Qt6 host QML tools already installed"
    fi
    
    # Check if Windows QML is installed
    if is_installed "qt6-windows-qml"; then
        echo_success "Qt6 Windows QML already built"
        return
    fi
    
    # Build qtshadertools for Windows
    echo_info "Building qtshadertools for Windows..."
    mkdir -p "$HOME_DIR/qt6-build-winarm64-shadertools"
    cd "$HOME_DIR/qt6-build-winarm64-shadertools"
    
    echo_verbose "  Configuring qtshadertools (Windows)..."
    cmake "$QT_SRC_DIR/qtshadertools" \
        -DCMAKE_TOOLCHAIN_FILE="$HOME_DIR/llvm-mingw-toolchain.cmake" \
        -DQT_HOST_PATH="$INSTALL_HOST_DIR" \
        -DCMAKE_PREFIX_PATH="$INSTALL_WIN_DIR" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_WIN_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_verbose "  Building qtshadertools (Windows)..."
    cmake --build . --parallel "$PARALLEL_JOBS" 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    cmake --install . 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    # Build qtdeclarative for Windows
    echo_info "Building qtdeclarative for Windows..."
    mkdir -p "$HOME_DIR/qt6-build-winarm64-declarative"
    cd "$HOME_DIR/qt6-build-winarm64-declarative"
    
    echo_verbose "  Configuring qtdeclarative (Windows)..."
    cmake "$QT_SRC_DIR/qtdeclarative" \
        -DCMAKE_TOOLCHAIN_FILE="$HOME_DIR/llvm-mingw-toolchain.cmake" \
        -DQT_HOST_PATH="$INSTALL_HOST_DIR" \
        -DCMAKE_PREFIX_PATH="$INSTALL_WIN_DIR" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_WIN_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_verbose "  Building qtdeclarative (Windows)..."
    cmake --build . --parallel "$PARALLEL_JOBS" 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    cmake --install . 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_success "Qt6 QML modules built successfully!"
}

# Create test application
create_test_app() {
    echo_info "Creating test application..."
    
    if is_installed "test-app"; then
        echo_success "Test application already exists at $HOME_DIR/qt6-hello-test"
        return
    fi
    
    TEST_DIR="$HOME_DIR/qt6-hello-test"
    mkdir -p "$TEST_DIR"
    
    echo_verbose "  Creating main.cpp..."
    cat > "$TEST_DIR/main.cpp" << 'EOF'
#include <QApplication>
#include <QPushButton>
#include <QVBoxLayout>
#include <QLabel>
#include <QWidget>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    QWidget window;
    window.setWindowTitle("Qt6 Hello World");
    window.resize(400, 200);

    QVBoxLayout *layout = new QVBoxLayout(&window);

    QLabel *label = new QLabel("Hello from Qt6!");
    label->setAlignment(Qt::AlignCenter);
    label->setStyleSheet("font-size: 18px; color: #2c3e50;");

    QPushButton *button = new QPushButton("Click Me!");
    button->setStyleSheet("padding: 10px; font-size: 14px;");

    QObject::connect(button, &QPushButton::clicked, [label]() {
        static int count = 0;
        count++;
        label->setText(QString("Button clicked %1 times!").arg(count));
    });

    layout->addWidget(label);
    layout->addWidget(button);

    window.show();

    return app.exec();
}
EOF

    echo_verbose "  Creating CMakeLists.txt..."
    cat > "$TEST_DIR/CMakeLists.txt" << 'EOF'
cmake_minimum_required(VERSION 3.16)

project(Qt6HelloWorld VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Widgets)

set(CMAKE_AUTOMOC ON)

add_executable(qt6hello
    main.cpp
)

target_link_libraries(qt6hello
    Qt6::Core
    Qt6::Widgets
)

if(WIN32)
    set_target_properties(qt6hello PROPERTIES
        WIN32_EXECUTABLE TRUE
    )
endif()
EOF

    echo_success "Test application created at $TEST_DIR"
}

# Build test application
build_test_app() {
    TEST_DIR="$HOME_DIR/qt6-hello-test"
    
    # Build for macOS
    echo_info "Building test application for macOS..."
    mkdir -p "$TEST_DIR/build-macos"
    cd "$TEST_DIR/build-macos"
    
    echo_verbose "  Configuring for macOS..."
    cmake .. \
        -DCMAKE_PREFIX_PATH="$INSTALL_HOST_DIR" \
        -DCMAKE_BUILD_TYPE=Release 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_verbose "  Building for macOS..."
    cmake --build . 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_success "macOS application built: $TEST_DIR/build-macos/qt6hello"
    echo_info "Run with: $TEST_DIR/build-macos/qt6hello"
    
    # Build for Windows
    echo_info "Building test application for Windows ARM64..."
    mkdir -p "$TEST_DIR/build-windows"
    cd "$TEST_DIR/build-windows"
    
    echo_verbose "  Configuring for Windows..."
    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE="$HOME_DIR/llvm-mingw-toolchain.cmake" \
        -DQT_HOST_PATH="$INSTALL_HOST_DIR" \
        -DCMAKE_PREFIX_PATH="$INSTALL_WIN_DIR" \
        -DCMAKE_BUILD_TYPE=Release 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_verbose "  Building for Windows..."
    cmake --build . 2>&1 | while IFS= read -r line; do
        echo_verbose "$line"
    done
    
    echo_success "Windows application built: $TEST_DIR/build-windows/qt6hello.exe"
    file "$TEST_DIR/build-windows/qt6hello.exe"
}

# Main installation flow
main() {
    echo_info "====================================="
    echo_info "Qt6 Cross-Compilation Setup"
    echo_info "macOS Sequoia -> Windows ARM64"
    echo_info "====================================="
    echo ""
    
    echo_info "Checking installation status..."
    echo ""
    
    check_prerequisites
    setup_llvm_mingw
    create_toolchain_file
    download_qt6_source
    build_qt6_host
    build_qt6_windows_base
    
    if [[ $BUILD_QML =~ ^[Yy]$ ]]; then
        build_qt6_windows_qml
    else
        echo_info "Skipping QML build (BUILD_QML not set to 'y')"
    fi
    
    create_test_app
    build_test_app
    
    echo ""
    echo_success "====================================="
    echo_success "Installation Complete!"
    echo_success "====================================="
    echo_info "Qt6 Host (macOS): $INSTALL_HOST_DIR"
    echo_info "Qt6 Windows: $INSTALL_WIN_DIR"
    echo_info "Test app: $HOME_DIR/qt6-hello-test"
    echo ""
    echo_info "Next steps:"
    echo_info "1. Test macOS app: $HOME_DIR/qt6-hello-test/build-macos/qt6hello"
    echo_info "2. Copy Windows app to Windows ARM64 device to test"
    echo ""
}

# Run main
main
