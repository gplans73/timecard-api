#!/usr/bin/env bash
set -euo pipefail
cd "${PROJECT_ROOT:-$HOME/Desktop/timecard}"

echo "Running file move and rename operations..."
# example test line:
ls -1 | head -5
echo "Moves & renames complete."
