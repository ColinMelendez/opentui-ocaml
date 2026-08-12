#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)

usage() {
  printf '%s\n' \
    "usage: sh packages/opentui-core/bench/trace_runtime_events.sh gc-stats [default|warmed]" \
    "       sh packages/opentui-core/bench/trace_runtime_events.sh trace OUTPUT.json [default|warmed]" >&2
  exit 2
}

if [ "$#" -lt 1 ]; then
  usage
fi

mode=$1
shift

profile_exe="$repo_dir/_build/default/packages/opentui-core/bench/profile.exe"
events_dir=

cleanup_events_dir() {
  if [ -n "$events_dir" ]; then
    rm -f "$events_dir"/*.events
    rmdir "$events_dir" 2>/dev/null || true
    events_dir=
  fi
}

trap cleanup_events_dir 0

run_gc_stats() {
  events_dir=$(mktemp -d "${TMPDIR:-/tmp}/opentui-runtime-events.XXXXXX")
  stats_status=0
  if [ "$workload" = warmed ]; then
    OPENTUI_PROFILE_WORKLOAD=warmed nix develop "$repo_dir#test" -c dune exec \
      olly -- gc-stats --dir "$events_dir" "$profile_exe" || stats_status=$?
  else
    nix develop "$repo_dir#test" -c dune exec \
      olly -- gc-stats --dir "$events_dir" "$profile_exe" || stats_status=$?
  fi
  if [ "$stats_status" -ne 0 ]; then
    exit "$stats_status"
  fi
}

run_trace() {
  events_dir=$(mktemp -d "${TMPDIR:-/tmp}/opentui-runtime-events.XXXXXX")
  trace_status=0
  if [ "$workload" = warmed ]; then
    OPENTUI_PROFILE_WORKLOAD=warmed nix develop "$repo_dir#test" -c dune exec \
      olly -- trace --dir "$events_dir" --format=json "$trace_file" \
      "$profile_exe" || trace_status=$?
  else
    nix develop "$repo_dir#test" -c dune exec \
      olly -- trace --dir "$events_dir" --format=json "$trace_file" \
      "$profile_exe" || trace_status=$?
  fi
  if [ "$trace_status" -ne 0 ]; then
    exit "$trace_status"
  fi
  if [ "$(tail -n 1 "$trace_file")" != "]" ]; then
    trace_temp=$(mktemp "$trace_file.XXXXXX")
    sed '$s/,$//' "$trace_file" > "$trace_temp"
    printf '%s\n' "]" >> "$trace_temp"
    mv "$trace_temp" "$trace_file"
  fi
}

case "$mode" in
  gc-stats)
    if [ "$#" -gt 1 ]; then
      usage
    fi
    workload=${1:-default}
    case "$workload" in
      default|warmed) ;;
      *) usage ;;
    esac
    cd "$repo_dir"
    nix develop "$repo_dir#test" -c dune build \
      --profile release ./packages/opentui-core/bench/profile.exe
    run_gc_stats
    ;;
  trace)
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
      usage
    fi
    trace_file=$1
    workload=${2:-default}
    case "$workload" in
      default|warmed) ;;
      *) usage ;;
    esac
    case "$trace_file" in
      /*) ;;
      *) trace_file="$repo_dir/$trace_file" ;;
    esac
    trace_dir=$(dirname -- "$trace_file")
    mkdir -p "$trace_dir"
    cd "$repo_dir"
    nix develop "$repo_dir#test" -c dune build \
      --profile release ./packages/opentui-core/bench/profile.exe
    run_trace
    ;;
  *)
    usage
    ;;
esac
