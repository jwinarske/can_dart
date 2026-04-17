#!/usr/bin/env bash
# Generate pubspec_overrides.yaml for packages and examples that depend on
# sibling packages in this monorepo. Used in CI where the gitignored override
# files don't exist.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

write_override() {
    local dir="$1"
    shift
    local file="$dir/pubspec_overrides.yaml"
    if [[ -f "$file" ]]; then
        return # already exists (local dev)
    fi
    echo "# Auto-generated for CI — resolve monorepo deps from path." > "$file"
    echo "dependency_overrides:" >> "$file"
    while [[ $# -gt 0 ]]; do
        local pkg="$1"
        local path="$2"
        shift 2
        echo "  $pkg:" >> "$file"
        echo "    path: $path" >> "$file"
    done
    echo "Created $file"
}

# Packages with internal dependencies
write_override "$REPO_ROOT/packages/can_engine" \
    can_dbc ../can_dbc

write_override "$REPO_ROOT/packages/nmea2000" \
    j1939 ../j1939 \
    can_codec ../can_codec

write_override "$REPO_ROOT/packages/nmea2000_bus" \
    nmea2000 ../nmea2000 \
    j1939 ../j1939 \
    can_codec ../can_codec

write_override "$REPO_ROOT/packages/rvc" \
    j1939 ../j1939 \
    can_codec ../can_codec

write_override "$REPO_ROOT/packages/rvc_bus" \
    rvc ../rvc \
    j1939 ../j1939 \
    can_codec ../can_codec

# Flutter examples
write_override "$REPO_ROOT/examples/obdii_monitor" \
    can_dbc ../../packages/can_dbc \
    can_engine ../../packages/can_engine

write_override "$REPO_ROOT/examples/throttle_ui" \
    can_dbc ../../packages/can_dbc

write_override "$REPO_ROOT/examples/instrument_display" \
    nmea2000 ../../packages/nmea2000 \
    nmea2000_bus ../../packages/nmea2000_bus \
    j1939 ../../packages/j1939 \
    can_codec ../../packages/can_codec

write_override "$REPO_ROOT/examples/rv_dashboard" \
    rvc ../../packages/rvc \
    rvc_bus ../../packages/rvc_bus \
    j1939 ../../packages/j1939 \
    can_codec ../../packages/can_codec
