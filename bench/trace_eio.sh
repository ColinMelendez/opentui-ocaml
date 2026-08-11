#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf '%s\n' "usage: sh bench/trace_eio.sh OUTPUT.fxt [default|warmed]" >&2
  exit 2
fi

if ! command -v eio-trace >/dev/null 2>&1; then
  printf '%s\n' \
    "eio-trace is not installed; install the optional eio-trace 0.4 tool first" >&2
  exit 127
fi

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
trace_file=$1
workload=${2:-default}
case "$workload" in
  default|warmed) ;;
  *)
    printf '%s\n' "workload must be default or warmed" >&2
    exit 2
    ;;
esac
trace_dir=$(dirname -- "$trace_file")
mkdir -p "$trace_dir"
cd "$repo_dir"

nix develop "$repo_dir#test" -c dune build \
  --profile release ./bench/profile.exe

if [ "$workload" = warmed ]; then
  exec eio-trace record -f "$trace_file" -- \
    nix develop "$repo_dir#test" -c \
    "$repo_dir/_build/default/bench/profile.exe" --workload warmed
else
  exec eio-trace record -f "$trace_file" -- \
    nix develop "$repo_dir#test" -c \
    "$repo_dir/_build/default/bench/profile.exe"
fi
