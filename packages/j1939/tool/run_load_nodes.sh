#!/usr/bin/env bash
# run_load_nodes.sh — J1939 stack load-test launcher.
#
# Builds bin/load_node.dart once, then spawns N AOT-compiled instances
# against a vcan interface. Forwards Ctrl-C / SIGTERM to all children and
# waits for them to drain.
#
# Why build once instead of N parallel `dart run`:
#   Parallel `dart run` invocations race on the hooks_runner build state
#   under .dart_tool/hooks_runner/ and can corrupt the cache. Building a
#   single AOT bundle sidesteps that and also makes each instance start
#   instantly (no Dart VM warm-up).
#
# Usage:
#   tool/run_load_nodes.sh <N> [iface] [-- extra-args-to-each-child...]
#
# Example:
#   tool/run_load_nodes.sh 8 vcan0
#   tool/run_load_nodes.sh 16 vcan0 -- --tx-hz=50 --bam-period=500
#
# Requirements:
#   • Linux with the vcan kernel module available.
#   • sudo (only if the interface doesn't already exist).
#   • A Dart SDK that supports `dart build cli` with native-asset build
#     hooks (Dart 3.6+ at time of writing; the command is still "in
#     preview" — we rely on it because plain `dart compile exe` does not
#     yet run build hooks).

set -uo pipefail

N="${1:-}"
IFACE="${2:-vcan0}"
# Extra args after `--` are passed verbatim to every child.
extra_args=()
if [[ $# -ge 3 ]]; then
  if [[ "$3" == "--" ]]; then
    extra_args=("${@:4}")
  else
    echo "usage: $0 <N> [iface] [-- extra-args...]" >&2
    exit 64
  fi
fi

if [[ -z "$N" ]]; then
  echo "usage: $0 <N> [iface] [-- extra-args...]" >&2
  exit 64
fi

if (( N < 1 || N > 126 )); then
  echo "N must be in [1, 126] (leaves headroom in J1939 address space)" >&2
  exit 64
fi

# Resolve package root (this script lives at $pkg/tool/).
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd -- "$here/.." && pwd)"
cd "$pkg"

# Ensure the vcan interface exists and is up.
if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "[run] creating $IFACE (requires sudo)"
  sudo modprobe vcan
  sudo ip link add dev "$IFACE" type vcan
  sudo ip link set up "$IFACE"
fi

# Resolve pub deps, then build the AOT CLI bundle. `dart build cli` runs
# hook/build.dart (producing libj1939_plugin.so) and assembles
#   <bundle>/bin/load_node
#   <bundle>/lib/libj1939_plugin.so
# which the exe resolves via its sibling-.so lookup at startup.
echo "[run] dart pub get"
dart pub get >/dev/null

bundle_root="$pkg/.dart_tool/load_node_bundle"
echo "[run] dart build cli -t bin/load_node.dart -> $bundle_root/bundle"
rm -rf "$bundle_root"
dart build cli -t bin/load_node.dart -o "$bundle_root" --verbosity=error
exe="$bundle_root/bundle/bin/load_node"
if [[ ! -x "$exe" ]]; then
  echo "[run] build failed — $exe not found" >&2
  exit 1
fi

pids=()
cleanup() {
  echo
  echo "[run] forwarding shutdown to ${#pids[@]} child(ren)"
  for pid in "${pids[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
}
trap cleanup INT TERM

echo "[run] spawning $N load_node instance(s) on $IFACE"
for ((i=0; i<N; i++)); do
  "$exe" --id="$i" --iface="$IFACE" "${extra_args[@]}" &
  pids+=("$!")
done

# Wait for every child to exit (either naturally or after the trap fires).
# Using per-pid wait so one child's early exit doesn't drop the others.
rc=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    child_rc=$?
    # 130 = SIGINT via trap, 143 = SIGTERM — treat those as clean.
    if (( child_rc != 130 && child_rc != 143 )); then
      rc=$child_rc
    fi
  fi
done

echo "[run] all children exited (rc=$rc)"
exit "$rc"
