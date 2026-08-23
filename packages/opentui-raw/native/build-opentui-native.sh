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

if command -v sha256sum >/dev/null 2>&1; then
  span_feed_hash=$(sha256sum "$upstream_dir/native-span-feed.zig" | awk '{print $1}')
  buffer_hash=$(sha256sum "$upstream_dir/buffer.zig" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  span_feed_hash=$(shasum -a 256 "$upstream_dir/native-span-feed.zig" | awk '{print $1}')
  buffer_hash=$(shasum -a 256 "$upstream_dir/buffer.zig" | awk '{print $1}')
else
  printf '%s\n' "the native source audit requires sha256sum or shasum" >&2
  exit 127
fi
if [ "$span_feed_hash" != "a41a8228e920a9250b44f9812240844ccfbcca4f803ebd29e2002374e80ecfbe" ]; then
  printf '%s\n' "pinned native-span-feed.zig does not match the audited source" >&2
  exit 1
fi
if [ "$buffer_hash" != "d702afe1c741d10d5d6e0cde52572454395f581d581c509809e654cc9e0a1c68" ]; then
  printf '%s\n' "pinned buffer.zig does not match the audited source" >&2
  exit 1
fi

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
patched_source_dir="$output_dir/opentui-native-source"
rm -rf "$patched_source_dir"
mkdir -p "$patched_source_dir"
cp -R "$upstream_dir"/. "$patched_source_dir"/
if ! command -v patch >/dev/null 2>&1; then
  printf '%s\n' "the native source patch requires the patch utility" >&2
  exit 127
fi
chmod u+w \
  "$patched_source_dir/native-span-feed.zig" \
  "$patched_source_dir/buffer.zig" \
  "$patched_source_dir/renderer.zig" \
  "$patched_source_dir/lib.zig"
(CDPATH= cd -- "$patched_source_dir" && patch -N -p0 < "$native_dir/span_feed_exports.patch")
(CDPATH= cd -- "$patched_source_dir" && patch -N -p0 < "$native_dir/hit_grid_exports.patch")
(CDPATH= cd -- "$patched_source_dir" && patch -N -p0 < "$native_dir/capability_probe_exports.patch")
(CDPATH= cd -- "$patched_source_dir" && zig build -Doptimize=ReleaseSafe --prefix "$zig_prefix")

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
cp -R "$patched_source_dir"/. "$probe_source_dir"/
rm -f "$probe_source_dir/lib.zig"
sed \
  -e 's/^const native_yoga =/pub const native_yoga =/' \
  -e 's/^export fn /pub export fn /' \
  -e 's/^const native_span_feed =/pub const native_span_feed =/' \
  "$patched_source_dir/lib.zig" > "$probe_source_dir/lib.zig"
sed 's/^export fn /pub export fn /' "$patched_source_dir/yoga.zig" > "$probe_source_dir/yoga.zig.probe"
mv "$probe_source_dir/yoga.zig.probe" "$probe_source_dir/yoga.zig"

(CDPATH= cd -- "$output_dir" && zig build --build-file "$native_dir/build.zig" -Doptimize=Debug -Dsource-root=abi-probe-source)

: > "$stamp"
