#!/usr/bin/env bash
# Run clang-format on all C/C++ sources checked by CI.
# Usage:
#   ./scripts/clang-format-check.sh          # check only (dry-run)
#   ./scripts/clang-format-check.sh --fix    # format in place
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

FILES=()
while IFS= read -r -d '' f; do
    FILES+=("$f")
done < <(
    find "$REPO_ROOT"/packages/can_engine/src \
         "$REPO_ROOT"/packages/j1939/src \
         "$REPO_ROOT"/packages/j1939/ffi \
        -type f \( -name '*.cpp' -o -name '*.cc' -o -name '*.hpp' -o -name '*.h' \) \
        -not -name 'dart_api_dl*' \
        -print0
)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No C/C++ files found."
    exit 0
fi

if [[ "${1:-}" == "--fix" ]]; then
    clang-format -i "${FILES[@]}"
    echo "Formatted ${#FILES[@]} files."
else
    if clang-format --dry-run -Werror "${FILES[@]}"; then
        echo "All ${#FILES[@]} files pass clang-format."
    else
        echo ""
        echo "Fix with:  ./scripts/clang-format-check.sh --fix"
        exit 1
    fi
fi
