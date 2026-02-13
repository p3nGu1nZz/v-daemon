# v-daemon

v-daemon is a lightweight daemon project and the dev harness for the Director/Worker self-improvement loop ("DirectorDev"). This repository provides POSIX shell helper scripts to build, check, and run the daemon and director agent; C++ sources and a CMake-based build may be added under /src later. Use scripts/setup.sh to fetch Catch2 into external/Catch2 for unit tests, and scripts/build.sh to run CMake and Ninja when project CMake files are present.

## Requirements

- cmake
- ninja
- A C/C++ toolchain (g++ or clang)

## Quick start

1. Install/setup required tools (Linux):

   sh scripts/setup.sh --yes

2. Run repository checks:

   sh scripts/check.sh

3. Build (out-of-source):

   mkdir -p build && cd build && cmake -G Ninja .. && ninja -j$(nproc 2>/dev/null || echo 2)

4. Run the daemon supervisor:

   sh scripts/run.sh [--monitor]

## Project layout

- build/ — out-of-source build directory
- external/ — external dependencies or third-party code
- scripts/ — helper scripts (setup, check, run)

## Tests and linting

Basic unit test support is available via Catch2 (scripts/setup.sh can fetch Catch2 into external/Catch2). To enable building and running tests, add a top-level CMakeLists.txt with test targets; use scripts/build.sh (cmake + ninja) or run ctest / ninja test after configuring the build.

## License

This project is provided under the terms in the LICENSE file in the repository root.

## Contributing

Contributions, issues, and feature requests are welcome via GitHub pull requests and issues.
