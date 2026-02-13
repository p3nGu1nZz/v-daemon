# v-daemon

v-daemon is a lightweight daemon project. This repository contains sources, a CMake-based build setup, and helper scripts to build, check, and run the daemon.

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

No test runner or linter was detected in the repository snapshot. Consider adding tests and linters as needed.

## License

This project is provided under the terms in the LICENSE file in the repository root.

## Contributing

Contributions, issues, and feature requests are welcome via GitHub pull requests and issues.
