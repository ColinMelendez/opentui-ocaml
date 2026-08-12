#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
reference_dir="$repo_dir/packages/opentui-core/reference"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/opentui-reference-compare.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

bun "$reference_dir/run_reference_parser.ts" \
  < "$reference_dir/terminal_vectors.tsv" \
  > "$temp_dir/reference"

nix develop "$repo_dir#test" -c dune exec --root "$repo_dir" \
  ./packages/opentui-core/reference/parse_terminal_vectors.exe \
  < "$reference_dir/terminal_vectors.tsv" \
  > "$temp_dir/ocaml"

diff -u "$temp_dir/reference" "$temp_dir/ocaml"
