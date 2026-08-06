#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  printf '%s\n' "usage: build-opentui-native.sh STAMP [OUTPUT ...]" >&2
  exit 2
fi

stamp=
for target in "$@"; do
  case "$target" in
    *.stamp) stamp=$target ;;
  esac
done
if [ -z "$stamp" ]; then
  printf '%s\n' "usage: build-opentui-native.sh STAMP [OUTPUT ...]" >&2
  exit 2
fi

if ! command -v zig >/dev/null 2>&1; then
  printf '%s\n' "OpenTUI Phase 1 requires Zig 0.16.0; enter the repository Nix shell first" >&2
  exit 127
fi

native_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$native_dir/../../.." && pwd)
upstream_dir="$project_root/vendor/opentui/packages/core/src/zig"

zig_version=$(zig version)
if [ "$zig_version" != "0.16.0" ]; then
  printf '%s\n' "OpenTUI Phase 1 requires Zig 0.16.0, found $zig_version" >&2
  exit 1
fi

stamp_dir=$(dirname -- "$stamp")
case "$stamp_dir" in
  /*) output_dir=$stamp_dir ;;
  *) output_dir=$(CDPATH= cd -- "$stamp_dir" && pwd) ;;
esac
mkdir -p "$output_dir"

case "$(uname -s):$(uname -m)" in
  Darwin:arm64)
    target_name=aarch64-macos
    library_name=libopentui.dylib
    ;;
  Darwin:x86_64)
    target_name=x86_64-macos
    library_name=libopentui.dylib
    ;;
  Linux:aarch64|Linux:arm64)
    target_name=aarch64-linux
    library_name=libopentui.so
    ;;
  Linux:x86_64)
    target_name=x86_64-linux
    library_name=libopentui.so
    ;;
  *)
    printf '%s\n' "unsupported host for the pinned OpenTUI native build: $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

zig_prefix="$output_dir/zig-out"
(CDPATH= cd -- "$upstream_dir" && zig build -Doptimize=ReleaseSafe --prefix "$zig_prefix")

artifact="$output_dir/lib/$target_name/$library_name"
if [ ! -f "$artifact" ]; then
  printf '%s\n' "pinned OpenTUI build did not produce $artifact" >&2
  exit 1
fi

cp "$artifact" "$output_dir/libopentui.dylib"
cp "$artifact" "$output_dir/libopentui.so"

probe_source_dir="$output_dir/abi-probe-source"
rm -rf "$probe_source_dir"
mkdir -p "$probe_source_dir"
cp -R "$upstream_dir"/. "$probe_source_dir"/
rm -f "$probe_source_dir/lib.zig"
sed 's/^export fn /pub export fn /' "$upstream_dir/lib.zig" > "$probe_source_dir/lib.zig"

(CDPATH= cd -- "$output_dir" && zig build --build-file "$native_dir/build.zig" -Doptimize=Debug -Dsource-root=abi-probe-source)

: > "$stamp"
