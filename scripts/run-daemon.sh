#!/usr/bin/env sh
# Simple helper to run the daemon locally
set -e
python3 "$(dirname "$0")/../cmd/daemon.py"
